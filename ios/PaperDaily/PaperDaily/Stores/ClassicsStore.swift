import Foundation

@MainActor
final class ClassicsStore: ObservableObject {
    @Published private(set) var feed: ClassicsFeed?
    @Published private(set) var isLoading = false
    @Published var lastErrorMessage: String?
    @Published var statusMessage: String?

    let settings: UserSettingsStore

    private let apiClient: ClassicsFeedFetching
    private let cache: ClassicFeedCache
    private let sampleFeedLoader: (() -> ClassicsFeed?)?

    init(
        settings: UserSettingsStore,
        apiClient: ClassicsFeedFetching = ClassicFeedAPIClient(),
        cache: ClassicFeedCache = ClassicFeedCache(),
        sampleFeedLoader: (() -> ClassicsFeed?)? = nil
    ) {
        self.settings = settings
        self.apiClient = apiClient
        self.cache = cache
        self.sampleFeedLoader = sampleFeedLoader
    }

    func bootstrap() async {
        do {
            if let cachedFeed = try cache.load() {
                feed = cachedFeed
            } else if let sampleFeed = sampleFeedLoader?() {
                feed = sampleFeed
                statusMessage = "当前展示的是经典论文示例数据。"
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
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteFeed = try await apiClient.fetchFeed(from: url)
            feed = remoteFeed
            try cache.save(remoteFeed)
            lastErrorMessage = nil
            statusMessage = "经典论文库已刷新，共 \(remoteFeed.paperCount) 篇。"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func papers(searchText: String = "", category: String? = nil) -> [ClassicPaper] {
        guard let feed else { return [] }
        return feed.papers.filter { paper in
            if let category, !category.isEmpty, paper.category != category {
                return false
            }
            return paper.matches(searchText: searchText)
        }
    }

    var availableCategories: [String] {
        let categories = Set(feed?.papers.map(\.category) ?? [])
        return categories.sorted()
    }

    var generatedAtDescription: String {
        guard let feed else { return "暂无" }
        return FeedDisplay.dateTimeString(from: feed.generatedAt)
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
}
