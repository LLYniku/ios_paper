import Foundation

@MainActor
final class NetworkStore: ObservableObject {
    enum Keys {
        static let favoriteNetworkIDs = "favoriteNetworkIDs"
        static let favoriteNetworkRecords = "favoriteNetworkRecords"
        static let readNetworkIDs = "readNetworkIDs"
    }

    @Published private(set) var feed: NetworkFeed?
    @Published private(set) var isLoading = false
    @Published private(set) var favoriteNetworkIDs: Set<String> = []
    @Published private(set) var favoriteNetworkRecords: [FavoriteNetworkRecord] = []
    @Published private(set) var readNetworkIDs: Set<String> = []
    @Published var lastErrorMessage: String?
    @Published var statusMessage: String?

    let settings: UserSettingsStore

    private let apiClient: NetworkFeedFetching
    private let cache: NetworkFeedCache
    private let userDefaults: UserDefaults
    private let sampleFeedLoader: (() -> NetworkFeed?)?

    init(
        settings: UserSettingsStore,
        apiClient: NetworkFeedFetching = NetworkFeedAPIClient(),
        cache: NetworkFeedCache = NetworkFeedCache(),
        userDefaults: UserDefaults = .standard,
        sampleFeedLoader: (() -> NetworkFeed?)? = nil
    ) {
        self.settings = settings
        self.apiClient = apiClient
        self.cache = cache
        self.userDefaults = userDefaults
        self.sampleFeedLoader = sampleFeedLoader
    }

    func bootstrap() async {
        favoriteNetworkRecords = loadFavoriteNetworkRecords()
        favoriteNetworkIDs = Set(favoriteNetworkRecords.map(\.id))
            .union(userDefaults.stringArray(forKey: Keys.favoriteNetworkIDs) ?? [])
        readNetworkIDs = Set(userDefaults.stringArray(forKey: Keys.readNetworkIDs) ?? [])

        do {
            if let cachedFeed = try cache.load() {
                feed = cachedFeed
                syncFavoriteRecords(with: cachedFeed)
            } else if let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "当前展示的是网络内容示例数据。"
                syncFavoriteRecords(with: sampleFeed)
            }
        } catch {
            lastErrorMessage = "读取网络内容缓存失败：\(error.localizedDescription)"
        }

        await refresh()
    }

    func refresh() async {
        guard let url = settings.resolvedNetworkURL() else {
            if feed == nil, let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "未找到网络内容数据源，已载入示例数据。"
                syncFavoriteRecords(with: sampleFeed)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteFeed = try await apiClient.fetchFeed(from: url)
            feed = remoteFeed
            syncFavoriteRecords(with: remoteFeed)
            try cache.save(remoteFeed)
            lastErrorMessage = nil
            statusMessage = "网络内容已刷新，共 \(remoteFeed.stats.recommendedCount) 条。"
        } catch {
            guard !isCancellation(error) else {
                lastErrorMessage = nil
                return
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func items(
        searchText: String = "",
        platform: String? = nil,
        unreadOnly: Bool = false,
        favoritesOnly: Bool = false
    ) -> [NetworkItem] {
        guard let feed else { return [] }
        return feed.items.filter { item in
            if favoritesOnly && !favoriteNetworkIDs.contains(item.id) {
                return false
            }
            if unreadOnly && readNetworkIDs.contains(item.id) {
                return false
            }
            if let platform, !platform.isEmpty, item.platform != platform {
                return false
            }
            return item.matches(searchText: searchText)
        }
    }

    func favoriteItems(
        searchText: String = "",
        unreadOnly: Bool = false
    ) -> [FavoriteNetworkRecord] {
        favoriteNetworkRecords
            .filter { record in
                if unreadOnly && readNetworkIDs.contains(record.id) {
                    return false
                }
                return record.item.matches(searchText: searchText)
            }
            .sorted(by: Self.sortFavoriteRecords)
    }

    var availablePlatforms: [String] {
        let platforms = Set(feed?.items.map(\.platform) ?? [])
        return platforms.sorted()
    }

    var generatedAtDescription: String {
        guard let feed else { return "暂无" }
        return FeedDisplay.dateTimeString(from: feed.generatedAt)
    }

    func isFavorite(_ itemID: String) -> Bool {
        favoriteNetworkIDs.contains(itemID)
    }

    func isRead(_ itemID: String) -> Bool {
        readNetworkIDs.contains(itemID)
    }

    func toggleFavorite(_ item: NetworkItem) {
        let itemID = item.id
        if favoriteNetworkIDs.contains(itemID) {
            favoriteNetworkIDs.remove(itemID)
            favoriteNetworkRecords.removeAll { $0.id == itemID }
        } else {
            favoriteNetworkIDs.insert(itemID)
            upsertFavoriteRecord(
                FavoriteNetworkRecord(
                    item: item,
                    recommendationDate: feed?.recommendationDate ?? FeedDisplay.localDateString(from: Date()),
                    favoritedAt: Date(),
                    rating: 0
                )
            )
        }
        persistFavoriteIDs()
        persistFavoriteRecords()
    }

    func toggleFavorite(_ itemID: String) {
        if let item = feed?.items.first(where: { $0.id == itemID }) {
            toggleFavorite(item)
            return
        }
        if favoriteNetworkIDs.contains(itemID) {
            favoriteNetworkIDs.remove(itemID)
            favoriteNetworkRecords.removeAll { $0.id == itemID }
            persistFavoriteIDs()
            persistFavoriteRecords()
        }
    }

    func toggleRead(_ itemID: String) {
        if readNetworkIDs.contains(itemID) {
            readNetworkIDs.remove(itemID)
        } else {
            readNetworkIDs.insert(itemID)
        }
        persistReadIDs()
    }

    func favoriteRating(_ itemID: String) -> Int {
        favoriteNetworkRecords.first(where: { $0.id == itemID })?.rating ?? 0
    }

    func setFavoriteRating(_ itemID: String, rating: Int) {
        guard let index = favoriteNetworkRecords.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let record = favoriteNetworkRecords[index]
        favoriteNetworkRecords[index] = FavoriteNetworkRecord(
            item: record.item,
            recommendationDate: record.recommendationDate,
            favoritedAt: record.favoritedAt,
            rating: rating
        )
        favoriteNetworkRecords.sort(by: Self.sortFavoriteRecords)
        persistFavoriteRecords()
    }

    static func makeSampleFeedLoader(bundle: Bundle) -> () -> NetworkFeed? {
        {
            guard let url = bundle.url(forResource: "sample_network", withExtension: "json") else {
                return nil
            }
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? NetworkFeedAPIClient().decodeFeed(from: data)
        }
    }

    private func persistFavoriteIDs() {
        userDefaults.set(Array(favoriteNetworkIDs).sorted(), forKey: Keys.favoriteNetworkIDs)
    }

    private func persistFavoriteRecords() {
        do {
            let data = try FeedCoding.encoder.encode(favoriteNetworkRecords)
            userDefaults.set(data, forKey: Keys.favoriteNetworkRecords)
        } catch {
            lastErrorMessage = "保存网络收藏失败：\(error.localizedDescription)"
        }
    }

    private func persistReadIDs() {
        userDefaults.set(Array(readNetworkIDs).sorted(), forKey: Keys.readNetworkIDs)
    }

    private func loadFavoriteNetworkRecords() -> [FavoriteNetworkRecord] {
        guard let data = userDefaults.data(forKey: Keys.favoriteNetworkRecords) else {
            return []
        }
        do {
            return try FeedCoding.decoder.decode([FavoriteNetworkRecord].self, from: data)
        } catch {
            lastErrorMessage = "读取网络收藏失败：\(error.localizedDescription)"
            return []
        }
    }

    private func syncFavoriteRecords(with feed: NetworkFeed) {
        var didChange = false
        for item in feed.items where favoriteNetworkIDs.contains(item.id) {
            if let index = favoriteNetworkRecords.firstIndex(where: { $0.id == item.id }) {
                let current = favoriteNetworkRecords[index]
                let updated = FavoriteNetworkRecord(
                    item: item,
                    recommendationDate: current.recommendationDate,
                    favoritedAt: current.favoritedAt,
                    rating: current.rating
                )
                if updated != current {
                    favoriteNetworkRecords[index] = updated
                    didChange = true
                }
            } else {
                favoriteNetworkRecords.append(
                    FavoriteNetworkRecord(
                        item: item,
                        recommendationDate: feed.recommendationDate,
                        favoritedAt: Date(),
                        rating: 0
                    )
                )
                didChange = true
            }
        }

        if didChange {
            favoriteNetworkRecords.sort(by: Self.sortFavoriteRecords)
            persistFavoriteRecords()
        }
    }

    private func upsertFavoriteRecord(_ record: FavoriteNetworkRecord) {
        if let index = favoriteNetworkRecords.firstIndex(where: { $0.id == record.id }) {
            favoriteNetworkRecords[index] = record
        } else {
            favoriteNetworkRecords.append(record)
        }
        favoriteNetworkRecords.sort(by: Self.sortFavoriteRecords)
    }

    private static func sortFavoriteRecords(lhs: FavoriteNetworkRecord, rhs: FavoriteNetworkRecord) -> Bool {
        if lhs.rating != rhs.rating {
            return lhs.rating > rhs.rating
        }
        if lhs.recommendationDate != rhs.recommendationDate {
            return lhs.recommendationDate > rhs.recommendationDate
        }
        if lhs.favoritedAt != rhs.favoritedAt {
            return lhs.favoritedAt > rhs.favoritedAt
        }
        return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
    }

    private func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }
        return false
    }
}
