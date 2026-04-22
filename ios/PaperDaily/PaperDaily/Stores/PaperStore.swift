import Foundation

protocol LocalNotificationScheduling {
    func requestAuthorization() async throws
    func scheduleDailyReminder(hour: Int, minute: Int) async throws
    func cancelDailyReminder()
}

@MainActor
final class PaperStore: ObservableObject {
    enum Keys {
        static let favoritePaperIDs = "favoritePaperIDs"
        static let favoritePaperRecords = "favoritePaperRecords"
        static let readPaperIDs = "readPaperIDs"
    }

    @Published private(set) var feed: PaperFeed?
    @Published private(set) var isLoading = false
    @Published private(set) var favoritePaperIDs: Set<String> = []
    @Published private(set) var favoritePaperRecords: [FavoritePaperRecord] = []
    @Published private(set) var readPaperIDs: Set<String> = []
    @Published var lastErrorMessage: String?
    @Published var statusMessage: String?

    let settings: UserSettingsStore

    private let apiClient: FeedFetching
    private let cache: FeedCache
    private let userDefaults: UserDefaults
    private let notificationScheduler: LocalNotificationScheduling
    private let sampleFeedLoader: (() -> PaperFeed?)?

    init(
        apiClient: FeedFetching = FeedAPIClient(),
        cache: FeedCache = FeedCache(),
        settings: UserSettingsStore,
        userDefaults: UserDefaults = .standard,
        notificationScheduler: LocalNotificationScheduling = LocalNotificationScheduler(),
        sampleFeedLoader: (() -> PaperFeed?)? = nil
    ) {
        self.apiClient = apiClient
        self.cache = cache
        self.settings = settings
        self.userDefaults = userDefaults
        self.notificationScheduler = notificationScheduler
        self.sampleFeedLoader = sampleFeedLoader
    }

    func bootstrap() async {
        favoritePaperRecords = loadFavoritePaperRecords()
        favoritePaperIDs = Set(favoritePaperRecords.map(\.id))
            .union(userDefaults.stringArray(forKey: Keys.favoritePaperIDs) ?? [])
        readPaperIDs = Set(userDefaults.stringArray(forKey: Keys.readPaperIDs) ?? [])

        do {
            if let cachedFeed = try cache.load() {
                feed = cachedFeed
                syncFavoriteRecords(with: cachedFeed)
            } else if let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "当前展示的是示例数据。"
                syncFavoriteRecords(with: sampleFeed)
            }
        } catch {
            lastErrorMessage = "读取本地缓存失败：\(error.localizedDescription)"
        }

        await refresh()
    }

    func refresh() async {
        guard let url = settings.resolvedFeedURL() else {
            if feed == nil, let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "未配置 Feed URL，已载入示例数据。"
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteFeed = try await apiClient.fetchLatestFeed(from: url)
            feed = remoteFeed
            syncFavoriteRecords(with: remoteFeed)
            try cache.save(remoteFeed)
            lastErrorMessage = nil
            statusMessage = "已刷新到 \(remoteFeed.recommendationDate) 的推荐。"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        guard let url = settings.resolvedFeedURL() else {
            lastErrorMessage = FeedAPIClientError.invalidURL.localizedDescription
            return
        }

        do {
            let remoteFeed = try await apiClient.fetchLatestFeed(from: url)
            statusMessage = "连接成功，拿到了 \(remoteFeed.papers.count) 篇论文。"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearCache() {
        do {
            try cache.clear()
            statusMessage = "已清除本地缓存。"
        } catch {
            lastErrorMessage = "清除缓存失败：\(error.localizedDescription)"
        }
    }

    func papers(
        searchText: String = "",
        category: String? = nil,
        unreadOnly: Bool = false,
        favoritesOnly: Bool = false
    ) -> [PaperItem] {
        guard let feed else { return [] }
        return feed.papers.filter { paper in
            if favoritesOnly && !favoritePaperIDs.contains(paper.id) {
                return false
            }
            if unreadOnly && readPaperIDs.contains(paper.id) {
                return false
            }
            if let category, !category.isEmpty, !paper.categories.contains(category) {
                return false
            }
            return paper.matches(searchText: searchText)
        }
    }

    func favoritePapers(
        searchText: String = "",
        unreadOnly: Bool = false
    ) -> [FavoritePaperRecord] {
        favoritePaperRecords
            .filter { record in
                if unreadOnly && readPaperIDs.contains(record.id) {
                    return false
                }
                return record.paper.matches(searchText: searchText)
            }
            .sorted { lhs, rhs in
                if lhs.recommendationDate != rhs.recommendationDate {
                    return lhs.recommendationDate > rhs.recommendationDate
                }
                return lhs.favoritedAt > rhs.favoritedAt
            }
    }

    var availableCategories: [String] {
        let categories = Set(feed?.papers.flatMap(\.categories) ?? [])
        return categories.sorted()
    }

    func isFavorite(_ paperID: String) -> Bool {
        favoritePaperIDs.contains(paperID)
    }

    func isRead(_ paperID: String) -> Bool {
        readPaperIDs.contains(paperID)
    }

    func toggleFavorite(_ paper: PaperItem) {
        let paperID = paper.id
        if favoritePaperIDs.contains(paperID) {
            favoritePaperIDs.remove(paperID)
            favoritePaperRecords.removeAll { $0.id == paperID }
        } else {
            favoritePaperIDs.insert(paperID)
            upsertFavoriteRecord(
                FavoritePaperRecord(
                    paper: paper,
                    recommendationDate: feed?.recommendationDate ?? FeedDisplay.localDateString(from: Date()),
                    favoritedAt: Date()
                )
            )
        }
        persistFavoriteIDs()
        persistFavoritePaperRecords()
    }

    func toggleFavorite(_ paperID: String) {
        if let paper = feed?.papers.first(where: { $0.id == paperID }) {
            toggleFavorite(paper)
            return
        }
        if favoritePaperIDs.contains(paperID) {
            favoritePaperIDs.remove(paperID)
            favoritePaperRecords.removeAll { $0.id == paperID }
            persistFavoriteIDs()
            persistFavoritePaperRecords()
        }
    }

    func toggleRead(_ paperID: String) {
        if readPaperIDs.contains(paperID) {
            readPaperIDs.remove(paperID)
        } else {
            readPaperIDs.insert(paperID)
        }
        persistReadIDs()
    }

    func setNotifications(enabled: Bool) async {
        if enabled {
            do {
                try await notificationScheduler.requestAuthorization()
                try await notificationScheduler.scheduleDailyReminder(
                    hour: settings.reminderHour,
                    minute: settings.reminderMinute
                )
                settings.notificationsEnabled = true
                statusMessage = "已启用每日本地提醒。"
                lastErrorMessage = nil
            } catch {
                settings.notificationsEnabled = false
                lastErrorMessage = error.localizedDescription
            }
        } else {
            notificationScheduler.cancelDailyReminder()
            settings.notificationsEnabled = false
            statusMessage = "已关闭每日本地提醒。"
        }
    }

    func updateReminder(at date: Date) async {
        settings.updateReminder(date: date)
        guard settings.notificationsEnabled else { return }
        do {
            try await notificationScheduler.scheduleDailyReminder(
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
            statusMessage = "提醒时间已更新。"
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    var generatedAtDescription: String {
        guard let feed else { return "暂无" }
        return FeedDisplay.dateTimeString(from: feed.generatedAt)
    }

    static func makeSampleFeedLoader(bundle: Bundle) -> () -> PaperFeed? {
        {
            guard let url = bundle.url(forResource: "sample_latest", withExtension: "json") else {
                return nil
            }
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? FeedAPIClient().decodeFeed(from: data)
        }
    }

    private func persistFavoriteIDs() {
        userDefaults.set(Array(favoritePaperIDs).sorted(), forKey: Keys.favoritePaperIDs)
    }

    private func persistFavoritePaperRecords() {
        do {
            let data = try FeedCoding.encoder.encode(favoritePaperRecords)
            userDefaults.set(data, forKey: Keys.favoritePaperRecords)
        } catch {
            lastErrorMessage = "保存收藏失败：\(error.localizedDescription)"
        }
    }

    private func persistReadIDs() {
        userDefaults.set(Array(readPaperIDs).sorted(), forKey: Keys.readPaperIDs)
    }

    private func loadFavoritePaperRecords() -> [FavoritePaperRecord] {
        guard let data = userDefaults.data(forKey: Keys.favoritePaperRecords) else {
            return []
        }
        do {
            return try FeedCoding.decoder.decode([FavoritePaperRecord].self, from: data)
        } catch {
            lastErrorMessage = "读取收藏失败：\(error.localizedDescription)"
            return []
        }
    }

    private func syncFavoriteRecords(with feed: PaperFeed) {
        var didChange = false
        for paper in feed.papers where favoritePaperIDs.contains(paper.id) {
            if let index = favoritePaperRecords.firstIndex(where: { $0.id == paper.id }) {
                let current = favoritePaperRecords[index]
                let updated = FavoritePaperRecord(
                    paper: paper,
                    recommendationDate: current.recommendationDate,
                    favoritedAt: current.favoritedAt
                )
                if updated != current {
                    favoritePaperRecords[index] = updated
                    didChange = true
                }
            } else {
                favoritePaperRecords.append(
                    FavoritePaperRecord(
                        paper: paper,
                        recommendationDate: feed.recommendationDate,
                        favoritedAt: Date()
                    )
                )
                didChange = true
            }
        }

        let filteredRecords = favoritePaperRecords.filter { favoritePaperIDs.contains($0.id) }
        if filteredRecords != favoritePaperRecords {
            favoritePaperRecords = filteredRecords
            didChange = true
        }

        if didChange {
            persistFavoriteIDs()
            persistFavoritePaperRecords()
        }
    }

    private func upsertFavoriteRecord(_ record: FavoritePaperRecord) {
        if let index = favoritePaperRecords.firstIndex(where: { $0.id == record.id }) {
            favoritePaperRecords[index] = record
        } else {
            favoritePaperRecords.append(record)
        }
    }
}
