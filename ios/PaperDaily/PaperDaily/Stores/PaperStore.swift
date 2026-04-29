import Foundation
import Combine

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
    @Published private(set) var isSubmittingPaper = false
    @Published var lastErrorMessage: String?
    @Published var statusMessage: String?

    let settings: UserSettingsStore

    private let apiClient: FeedFetching
    private let cache: FeedCache
    private let syncStore: AppSyncStore
    private let syncRemoteClient: AppSyncRemoteServing
    private let notificationScheduler: LocalNotificationScheduling
    private let sampleFeedLoader: (() -> PaperFeed?)?
    private var cancellables = Set<AnyCancellable>()

    init(
        apiClient: FeedFetching = FeedAPIClient(),
        cache: FeedCache = FeedCache(),
        settings: UserSettingsStore,
        syncStore: AppSyncStore,
        syncRemoteClient: AppSyncRemoteServing = AppSyncRemoteClient(),
        notificationScheduler: LocalNotificationScheduling = LocalNotificationScheduler(),
        sampleFeedLoader: (() -> PaperFeed?)? = nil
    ) {
        self.apiClient = apiClient
        self.cache = cache
        self.settings = settings
        self.syncStore = syncStore
        self.syncRemoteClient = syncRemoteClient
        self.notificationScheduler = notificationScheduler
        self.sampleFeedLoader = sampleFeedLoader

        favoritePaperRecords = syncStore.paperFavoriteRecords
        favoritePaperIDs = Set(syncStore.paperFavoriteRecords.map(\.id))
        readPaperIDs = syncStore.paperReadIDs
        bindSyncState()
    }

    func bootstrap() async {
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

    func submitPaperToToday(urlString: String) async {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            lastErrorMessage = "请先输入 arXiv 论文链接。"
            return
        }
        guard let configuration = settings.resolvedSyncConfiguration() else {
            lastErrorMessage = "请先在设置中配置远端同步的 Worker URL 和 Sync Token。"
            return
        }

        isSubmittingPaper = true
        defer { isSubmittingPaper = false }

        do {
            let response = try await syncRemoteClient.submitPaper(urlString: trimmedURL, configuration: configuration)
            guard response.accepted else {
                lastErrorMessage = "GitHub Actions 未接受本次论文分析请求。"
                return
            }
            lastErrorMessage = nil
            statusMessage = "已提交到 GitHub Actions。生成完成后，下拉刷新今日列表即可看到新论文。"
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
            .sorted(by: Self.sortFavoriteRecords)
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
                    favoritedAt: Date(),
                    rating: 0
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

    func favoriteRating(_ paperID: String) -> Int {
        favoritePaperRecords.first(where: { $0.id == paperID })?.rating ?? 0
    }

    func setFavoriteRating(_ paperID: String, rating: Int) {
        guard let index = favoritePaperRecords.firstIndex(where: { $0.id == paperID }) else {
            return
        }
        let record = favoritePaperRecords[index]
        favoritePaperRecords[index] = FavoritePaperRecord(
            paper: record.paper,
            recommendationDate: record.recommendationDate,
            favoritedAt: record.favoritedAt,
            rating: rating
        )
        favoritePaperRecords.sort(by: Self.sortFavoriteRecords)
        persistFavoritePaperRecords()
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
        syncStore.setPaperFavoriteRecords(favoritePaperRecords)
    }

    private func persistFavoritePaperRecords() {
        syncStore.setPaperFavoriteRecords(favoritePaperRecords)
    }

    private func persistReadIDs() {
        syncStore.setPaperReadIDs(readPaperIDs)
    }

    private func syncFavoriteRecords(with feed: PaperFeed) {
        var didChange = false
        for paper in feed.papers where favoritePaperIDs.contains(paper.id) {
            if let index = favoritePaperRecords.firstIndex(where: { $0.id == paper.id }) {
                let current = favoritePaperRecords[index]
                let updated = FavoritePaperRecord(
                    paper: paper,
                    recommendationDate: current.recommendationDate,
                    favoritedAt: current.favoritedAt,
                    rating: current.rating
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
                        favoritedAt: Date(),
                        rating: 0
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
            favoritePaperRecords.sort(by: Self.sortFavoriteRecords)
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
        favoritePaperRecords.sort(by: Self.sortFavoriteRecords)
    }

    private static func sortFavoriteRecords(lhs: FavoritePaperRecord, rhs: FavoritePaperRecord) -> Bool {
        if lhs.rating != rhs.rating {
            return lhs.rating > rhs.rating
        }
        if lhs.recommendationDate != rhs.recommendationDate {
            return lhs.recommendationDate > rhs.recommendationDate
        }
        if lhs.favoritedAt != rhs.favoritedAt {
            return lhs.favoritedAt > rhs.favoritedAt
        }
        return lhs.paper.title.localizedCaseInsensitiveCompare(rhs.paper.title) == .orderedAscending
    }

    private func bindSyncState() {
        syncStore.$paperFavoriteRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.favoritePaperRecords = records
                self?.favoritePaperIDs = Set(records.map(\.id))
            }
            .store(in: &cancellables)

        syncStore.$paperReadIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] readIDs in
                self?.readPaperIDs = readIDs
            }
            .store(in: &cancellables)
    }
}
