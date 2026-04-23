import Foundation
import Combine

@MainActor
final class ClassicsStore: ObservableObject {
    enum Keys {
        static let favoriteClassicIDs = "favoriteClassicIDs"
        static let favoriteClassicRecords = "favoriteClassicRecords"
        static let readClassicIDs = "readClassicIDs"
    }

    @Published private(set) var feed: ClassicsFeed?
    @Published private(set) var isLoading = false
    @Published private(set) var favoriteClassicIDs: Set<String> = []
    @Published private(set) var favoriteClassicRecords: [FavoriteClassicRecord] = []
    @Published private(set) var readClassicIDs: Set<String> = []
    @Published var lastErrorMessage: String?
    @Published var statusMessage: String?

    let settings: UserSettingsStore

    private let apiClient: ClassicsFeedFetching
    private let cache: ClassicFeedCache
    private let syncStore: AppSyncStore
    private let sampleFeedLoader: (() -> ClassicsFeed?)?
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: UserSettingsStore,
        apiClient: ClassicsFeedFetching = ClassicFeedAPIClient(),
        cache: ClassicFeedCache = ClassicFeedCache(),
        syncStore: AppSyncStore,
        sampleFeedLoader: (() -> ClassicsFeed?)? = nil
    ) {
        self.settings = settings
        self.apiClient = apiClient
        self.cache = cache
        self.syncStore = syncStore
        self.sampleFeedLoader = sampleFeedLoader

        favoriteClassicRecords = syncStore.classicFavoriteRecords
        favoriteClassicIDs = Set(syncStore.classicFavoriteRecords.map(\.id))
        readClassicIDs = syncStore.classicReadIDs
        bindSyncState()
    }

    func bootstrap() async {
        do {
            if let cachedFeed = try cache.load() {
                feed = cachedFeed
                syncFavoriteRecords(with: cachedFeed)
            } else if let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "当前展示的是经典论文示例数据。"
                syncFavoriteRecords(with: sampleFeed)
            }
        } catch {
            lastErrorMessage = "读取经典论文缓存失败：\(error.localizedDescription)"
        }

        await refresh()
    }

    func refresh() async {
        guard let url = settings.resolvedClassicsURL() else {
            if feed == nil, let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "未找到经典论文数据源，已载入示例数据。"
                syncFavoriteRecords(with: sampleFeed)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteFeed = try await apiClient.fetchFeed(from: url)
            let preferredFeed = richerFeed(current: feed, incoming: remoteFeed)
            feed = preferredFeed
            syncFavoriteRecords(with: preferredFeed)
            try cache.save(preferredFeed)
            lastErrorMessage = nil
            if preferredFeed.generatedAt == remoteFeed.generatedAt {
                statusMessage = "经典论文库已刷新，共 \(remoteFeed.paperCount) 篇。"
            } else {
                statusMessage = "远程经典库仍是旧版本，已保留本地较完整的数据。"
            }
        } catch {
            guard !isCancellation(error) else {
                lastErrorMessage = nil
                return
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func papers(
        searchText: String = "",
        category: String? = nil,
        unreadOnly: Bool = false,
        favoritesOnly: Bool = false
    ) -> [ClassicPaper] {
        guard let feed else { return [] }
        return feed.papers
            .filter { paper in
                if favoritesOnly && !favoriteClassicIDs.contains(paper.id) {
                    return false
                }
                if unreadOnly && readClassicIDs.contains(paper.id) {
                    return false
                }
                if let category, !category.isEmpty, paper.category != category {
                    return false
                }
                return paper.matches(searchText: searchText)
            }
            .sorted(by: Self.sortPapers)
    }

    func favoritePapers(
        searchText: String = "",
        unreadOnly: Bool = false
    ) -> [FavoriteClassicRecord] {
        favoriteClassicRecords
            .filter { record in
                if unreadOnly && readClassicIDs.contains(record.id) {
                    return false
                }
                return record.paper.matches(searchText: searchText)
            }
            .sorted(by: Self.sortFavoriteRecords)
    }

    var availableCategories: [String] {
        let categories = Set(feed?.papers.map(\.category) ?? [])
        return categories.sorted()
    }

    var generatedAtDescription: String {
        guard let feed else { return "暂无" }
        return FeedDisplay.dateTimeString(from: feed.generatedAt)
    }

    func isFavorite(_ paperID: String) -> Bool {
        favoriteClassicIDs.contains(paperID)
    }

    func isRead(_ paperID: String) -> Bool {
        readClassicIDs.contains(paperID)
    }

    func toggleFavorite(_ paper: ClassicPaper) {
        let paperID = paper.id
        if favoriteClassicIDs.contains(paperID) {
            favoriteClassicIDs.remove(paperID)
            favoriteClassicRecords.removeAll { $0.id == paperID }
        } else {
            favoriteClassicIDs.insert(paperID)
            upsertFavoriteRecord(
                FavoriteClassicRecord(
                    paper: paper,
                    favoritedAt: Date(),
                    rating: 0
                )
            )
        }
        persistFavoriteIDs()
        persistFavoriteRecords()
    }

    func toggleFavorite(_ paperID: String) {
        if let paper = feed?.papers.first(where: { $0.id == paperID }) {
            toggleFavorite(paper)
            return
        }
        if favoriteClassicIDs.contains(paperID) {
            favoriteClassicIDs.remove(paperID)
            favoriteClassicRecords.removeAll { $0.id == paperID }
            persistFavoriteIDs()
            persistFavoriteRecords()
        }
    }

    func toggleRead(_ paperID: String) {
        if readClassicIDs.contains(paperID) {
            readClassicIDs.remove(paperID)
        } else {
            readClassicIDs.insert(paperID)
        }
        persistReadIDs()
    }

    func favoriteRating(_ paperID: String) -> Int {
        favoriteClassicRecords.first(where: { $0.id == paperID })?.rating ?? 0
    }

    func setFavoriteRating(_ paperID: String, rating: Int) {
        guard let index = favoriteClassicRecords.firstIndex(where: { $0.id == paperID }) else {
            return
        }
        let record = favoriteClassicRecords[index]
        favoriteClassicRecords[index] = FavoriteClassicRecord(
            paper: record.paper,
            favoritedAt: record.favoritedAt,
            rating: rating
        )
        favoriteClassicRecords.sort(by: Self.sortFavoriteRecords)
        persistFavoriteRecords()
    }

    static func makeSampleFeedLoader(bundle: Bundle) -> () -> ClassicsFeed? {
        {
            guard let url = bundle.url(forResource: "sample_classics", withExtension: "json") else {
                return nil
            }
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? ClassicFeedAPIClient().decodeFeed(from: data)
        }
    }

    private static func sortPapers(lhs: ClassicPaper, rhs: ClassicPaper) -> Bool {
        if lhs.year != rhs.year {
            return (lhs.year ?? Int.min) > (rhs.year ?? Int.min)
        }
        if lhs.venue != rhs.venue {
            return (lhs.venue ?? lhs.publication) < (rhs.venue ?? rhs.publication)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func persistFavoriteIDs() {
        syncStore.setClassicFavoriteRecords(favoriteClassicRecords)
    }

    private func persistFavoriteRecords() {
        syncStore.setClassicFavoriteRecords(favoriteClassicRecords)
    }

    private func persistReadIDs() {
        syncStore.setClassicReadIDs(readClassicIDs)
    }

    private func syncFavoriteRecords(with feed: ClassicsFeed) {
        var didChange = false
        for paper in feed.papers where favoriteClassicIDs.contains(paper.id) {
            if let index = favoriteClassicRecords.firstIndex(where: { $0.id == paper.id }) {
                let current = favoriteClassicRecords[index]
                let updated = FavoriteClassicRecord(
                    paper: paper,
                    favoritedAt: current.favoritedAt,
                    rating: current.rating
                )
                if updated != current {
                    favoriteClassicRecords[index] = updated
                    didChange = true
                }
            } else {
                favoriteClassicRecords.append(
                    FavoriteClassicRecord(
                        paper: paper,
                        favoritedAt: Date(),
                        rating: 0
                    )
                )
                didChange = true
            }
        }

        favoriteClassicRecords.removeAll { record in
            !favoriteClassicIDs.contains(record.id)
        }

        if didChange {
            favoriteClassicRecords.sort(by: Self.sortFavoriteRecords)
            persistFavoriteRecords()
        }
    }

    private func upsertFavoriteRecord(_ record: FavoriteClassicRecord) {
        if let index = favoriteClassicRecords.firstIndex(where: { $0.id == record.id }) {
            favoriteClassicRecords[index] = record
        } else {
            favoriteClassicRecords.append(record)
        }
        favoriteClassicRecords.sort(by: Self.sortFavoriteRecords)
    }

    private static func sortFavoriteRecords(lhs: FavoriteClassicRecord, rhs: FavoriteClassicRecord) -> Bool {
        if lhs.rating != rhs.rating {
            return lhs.rating > rhs.rating
        }
        if lhs.paper.year != rhs.paper.year {
            return (lhs.paper.year ?? Int.min) > (rhs.paper.year ?? Int.min)
        }
        if lhs.favoritedAt != rhs.favoritedAt {
            return lhs.favoritedAt > rhs.favoritedAt
        }
        return lhs.paper.title.localizedCaseInsensitiveCompare(rhs.paper.title) == .orderedAscending
    }

    private func richerFeed(current: ClassicsFeed?, incoming: ClassicsFeed) -> ClassicsFeed {
        guard let current else { return incoming }
        if richnessScore(in: incoming) > richnessScore(in: current) {
            return incoming
        }
        if richnessScore(in: incoming) < richnessScore(in: current) {
            return current
        }
        return incoming.generatedAt >= current.generatedAt ? incoming : current
    }

    private func richnessScore(in feed: ClassicsFeed) -> Int {
        let summaryCount = feed.papers.reduce(into: 0) { count, paper in
            if !(paper.summaryZh ?? "").isEmpty || !(paper.tldr ?? "").isEmpty || !(paper.simpleIntro ?? "").isEmpty {
                count += 1
            }
        }
        let chineseCardCount = feed.papers.reduce(into: 0) { count, paper in
            if containsChinese(paper.cardSummary) {
                count += 1
            }
        }
        return summaryCount * 10 + chineseCardCount
    }

    private func containsChinese(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if case ClassicFeedAPIClientError.networkError(let message) = error {
            return message.localizedCaseInsensitiveContains("cancelled")
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("cancelled")
    }

    private func bindSyncState() {
        syncStore.$classicFavoriteRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.favoriteClassicRecords = records
                self?.favoriteClassicIDs = Set(records.map(\.id))
            }
            .store(in: &cancellables)

        syncStore.$classicReadIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] readIDs in
                self?.readClassicIDs = readIDs
            }
            .store(in: &cancellables)
    }
}
