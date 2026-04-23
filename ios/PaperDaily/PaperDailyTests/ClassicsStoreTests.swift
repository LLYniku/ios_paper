import Foundation
import XCTest
@testable import PaperDaily

@MainActor
final class ClassicsStoreTests: XCTestCase {
    func testClassicCardsPreferChineseSummary() throws {
        let feed = MockClassicsFeedAPIClient.sampleFeed

        XCTAssertEqual(feed.papers.first?.cardSummary, "中文简介：这是一篇关于压缩大语言模型的经典论文。")
    }

    func testClassicsAreSortedNewestFirst() async throws {
        let defaults = try makeDefaults()
        let (store, _) = makeStore(defaults: defaults)

        await store.bootstrap()

        let years = store.papers().compactMap(\.year)
        XCTAssertEqual(years, [2025, 2023, 2021])
    }

    func testFavoriteClassicPersistsAcrossRefreshes() async throws {
        let defaults = try makeDefaults()
        let apiClient = MutableMockClassicsFeedAPIClient(feed: MockClassicsFeedAPIClient.sampleFeed)
        let (store, _) = makeStore(defaults: defaults, apiClient: apiClient)

        await store.bootstrap()
        let paper = try XCTUnwrap(store.feed?.papers.first)
        store.toggleFavorite(paper)

        apiClient.feed = MockClassicsFeedAPIClient.olderFeed
        await store.refresh()

        let favorites = store.favoritePapers()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.paper.id, paper.id)
        XCTAssertTrue(store.isFavorite(paper.id))
    }

    func testReadClassicPersists() async throws {
        let defaults = try makeDefaults()
        let (store, syncStore) = makeStore(defaults: defaults)

        await store.bootstrap()
        let paperID = try XCTUnwrap(store.feed?.papers.first?.id)
        store.toggleRead(paperID)

        XCTAssertTrue(store.isRead(paperID))
        XCTAssertEqual(syncStore.classicReadIDs, [paperID])
    }

    func testCancelledRefreshDoesNotShowError() async throws {
        let defaults = try makeDefaults()
        let (store, _) = makeStore(
            defaults: defaults,
            apiClient: CancelledMockClassicsFeedAPIClient()
        )

        await store.bootstrap()

        XCTAssertNil(store.lastErrorMessage)
    }

    func testFavoriteClassicRatingPersistsAndSortsHigherFirst() async throws {
        let defaults = try makeDefaults()
        let (store, _) = makeStore(defaults: defaults)

        await store.bootstrap()
        let papers = try XCTUnwrap(store.feed?.papers)
        store.toggleFavorite(papers[0])
        store.toggleFavorite(papers[1])
        store.setFavoriteRating(papers[1].id, rating: 5)
        store.setFavoriteRating(papers[0].id, rating: 2)

        let favorites = store.favoritePapers()
        XCTAssertEqual(favorites.map(\.id), [papers[1].id, papers[0].id])
        XCTAssertEqual(favorites.map(\.rating), [5, 2])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "ClassicsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(
        defaults: UserDefaults,
        apiClient: ClassicsFeedFetching = MockClassicsFeedAPIClient()
    ) -> (ClassicsStore, AppSyncStore) {
        let syncStore = AppSyncStore(defaults: defaults)
        syncStore.start()
        let settings = UserSettingsStore(syncStore: syncStore)
        let cache = ClassicFeedCache(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = ClassicsStore(
            settings: settings,
            apiClient: apiClient,
            cache: cache,
            syncStore: syncStore,
            sampleFeedLoader: { MockClassicsFeedAPIClient.sampleFeed }
        )
        return (store, syncStore)
    }
}

private struct MockClassicsFeedAPIClient: ClassicsFeedFetching {
    static let sampleFeed: ClassicsFeed = {
        let json = """
        {
          "schema_version": "1.0",
          "generated_at": "2026-04-22T22:00:00Z",
          "source_title": "Awesome LLM Compression",
          "source_repo": "https://github.com/example/Awesome-LLM-Compression",
          "readme_path": "README.md",
          "paper_count": 3,
          "categories": ["Survey", "Quantization", "Pruning"],
          "papers": [
            {
              "id": "classic:survey-2025",
              "title": "Latest Survey",
              "category": "Survey",
              "publication": "NeurIPS 2025",
              "venue": "NeurIPS",
              "year": 2025,
              "paper_url": "https://arxiv.org/abs/2501.00001",
              "code_url": null,
              "project_url": null,
              "abstract": "English abstract latest.",
              "summary_zh": "中文简介：这是一篇关于压缩大语言模型的经典论文。",
              "tldr": "中文 TLDR",
              "simple_intro": "更短的中文介绍"
            },
            {
              "id": "classic:quant-2023",
              "title": "Quantization Paper",
              "category": "Quantization",
              "publication": "ICML 2023",
              "venue": "ICML",
              "year": 2023,
              "paper_url": "https://arxiv.org/abs/2301.00002",
              "code_url": "https://github.com/example/quant",
              "project_url": null,
              "abstract": "English abstract quant.",
              "summary_zh": "中文简介：量化方向代表工作。",
              "tldr": "中文 TLDR",
              "simple_intro": "量化短介绍"
            },
            {
              "id": "classic:prune-2021",
              "title": "Pruning Paper",
              "category": "Pruning",
              "publication": "ACL 2021",
              "venue": "ACL",
              "year": 2021,
              "paper_url": "https://arxiv.org/abs/2101.00003",
              "code_url": null,
              "project_url": "https://example.com/prune",
              "abstract": "English abstract prune.",
              "summary_zh": "中文简介：剪枝方向代表工作。",
              "tldr": "中文 TLDR",
              "simple_intro": "剪枝短介绍"
            }
          ]
        }
        """
        return try! ClassicFeedAPIClient().decodeFeed(from: Data(json.utf8))
    }()

    static let olderFeed: ClassicsFeed = {
        let json = """
        {
          "schema_version": "1.0",
          "generated_at": "2026-04-20T22:00:00Z",
          "source_title": "Awesome LLM Compression",
          "source_repo": "https://github.com/example/Awesome-LLM-Compression",
          "readme_path": "README.md",
          "paper_count": 1,
          "categories": ["Quantization"],
          "papers": [
            {
              "id": "classic:quant-2023",
              "title": "Quantization Paper",
              "category": "Quantization",
              "publication": "ICML 2023",
              "venue": "ICML",
              "year": 2023,
              "paper_url": "https://arxiv.org/abs/2301.00002",
              "code_url": null,
              "project_url": null,
              "abstract": "English abstract quant.",
              "summary_zh": "中文简介：量化方向代表工作。",
              "tldr": "中文 TLDR",
              "simple_intro": "量化短介绍"
            }
          ]
        }
        """
        return try! ClassicFeedAPIClient().decodeFeed(from: Data(json.utf8))
    }()

    func fetchFeed(from url: URL) async throws -> ClassicsFeed {
        Self.sampleFeed
    }

    func decodeFeed(from data: Data) throws -> ClassicsFeed {
        try ClassicFeedAPIClient().decodeFeed(from: data)
    }
}

private final class MutableMockClassicsFeedAPIClient: ClassicsFeedFetching {
    var feed: ClassicsFeed

    init(feed: ClassicsFeed) {
        self.feed = feed
    }

    func fetchFeed(from url: URL) async throws -> ClassicsFeed {
        feed
    }

    func decodeFeed(from data: Data) throws -> ClassicsFeed {
        try ClassicFeedAPIClient().decodeFeed(from: data)
    }
}

private struct CancelledMockClassicsFeedAPIClient: ClassicsFeedFetching {
    func fetchFeed(from url: URL) async throws -> ClassicsFeed {
        throw URLError(.cancelled)
    }

    func decodeFeed(from data: Data) throws -> ClassicsFeed {
        try ClassicFeedAPIClient().decodeFeed(from: data)
    }
}
