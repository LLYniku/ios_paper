import Foundation
import XCTest
@testable import PaperDaily

@MainActor
final class PaperStoreTests: XCTestCase {
    func testFavoriteStatePersists() async throws {
        let defaults = try makeDefaults()
        let (store, syncStore) = makeStore(defaults: defaults)

        await store.bootstrap()
        store.toggleFavorite("arxiv:2604.22001")

        XCTAssertEqual(syncStore.paperFavoriteRecords.map(\.id), ["arxiv:2604.22001"])
        XCTAssertTrue(store.isFavorite("arxiv:2604.22001"))
        XCTAssertEqual(store.favoritePapers().map(\.id), ["arxiv:2604.22001"])
    }

    func testReadStatePersists() async throws {
        let defaults = try makeDefaults()
        let (store, syncStore) = makeStore(defaults: defaults)

        store.toggleRead("arxiv:2604.22001")

        XCTAssertEqual(syncStore.paperReadIDs, ["arxiv:2604.22001"])
        XCTAssertTrue(store.isRead("arxiv:2604.22001"))
    }

    func testFavoritePaperPersistsAcrossFeedRefreshes() async throws {
        let defaults = try makeDefaults()
        let apiClient = MutableMockFeedAPIClient(feed: MockFeedAPIClient.sampleFeed)
        let (store, _) = makeStore(defaults: defaults, apiClient: apiClient)

        await store.bootstrap()
        store.toggleFavorite("arxiv:2604.22001")

        apiClient.feed = MockFeedAPIClient.emptyFeed
        await store.refresh()

        let favorites = store.favoritePapers()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.paper.id, "arxiv:2604.22001")
        XCTAssertEqual(favorites.first?.recommendationDate, "2026-04-23")
    }

    func testFavoritePaperKeepsContextNote() async throws {
        let defaults = try makeDefaults()
        let (store, _) = makeStore(defaults: defaults)

        await store.bootstrap()
        store.toggleFavorite("arxiv:2604.22001")

        let favorite = try XCTUnwrap(store.favoritePapers().first)
        XCTAssertEqual(favorite.contextNote, "arXiv：2026-04-22 · 收藏自：2026-04-23")
    }

    func testFavoriteRatingPersistsAndSortsHigherFirst() async throws {
        let defaults = try makeDefaults()
        let (store, _) = makeStore(defaults: defaults)

        await store.bootstrap()
        store.toggleFavorite("arxiv:2604.22001")
        store.toggleFavorite("arxiv:2604.22002")
        store.setFavoriteRating("arxiv:2604.22002", rating: 5)
        store.setFavoriteRating("arxiv:2604.22001", rating: 3)

        let favorites = store.favoritePapers()
        XCTAssertEqual(favorites.map(\.id), ["arxiv:2604.22002", "arxiv:2604.22001"])
        XCTAssertEqual(favorites.map(\.rating), [5, 3])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "PaperStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(
        defaults: UserDefaults,
        apiClient: FeedFetching = MockFeedAPIClient()
    ) -> (PaperStore, AppSyncStore) {
        let syncStore = AppSyncStore(defaults: defaults)
        syncStore.start()
        let settings = UserSettingsStore(syncStore: syncStore)
        let cache = FeedCache(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let store = PaperStore(
            apiClient: apiClient,
            cache: cache,
            settings: settings,
            syncStore: syncStore,
            notificationScheduler: MockNotificationScheduler(),
            sampleFeedLoader: { MockFeedAPIClient.sampleFeed }
        )
        return (store, syncStore)
    }
}

private struct MockFeedAPIClient: FeedFetching {
    static let sampleFeed: PaperFeed = {
        let json = """
        {
          "schema_version": "1.0",
          "generated_at": "2026-04-22T22:00:00Z",
          "recommendation_date": "2026-04-23",
          "timezone": "Asia/Taipei",
          "source": ["arxiv"],
          "language": "zh-Hans",
          "config": {
            "categories": ["cs.AI"],
            "max_paper_num": 30,
            "model": "gpt-5.4-mini"
          },
          "stats": {
            "total_candidates": 2,
            "recommended_count": 2,
            "llm_summary_count": 2
          },
          "papers": [
            {
              "id": "arxiv:2604.22001",
              "source": "arxiv",
              "title": "Sample",
              "authors": ["A", "B"],
              "abstract": "Abstract",
              "summary_zh": "总结",
              "tldr": "一句话",
              "recommendation_reason": "推荐理由",
              "relevance_score": 0.9,
              "published_at": "2026-04-22T00:00:00Z",
              "updated_at": "2026-04-22T01:00:00Z",
              "categories": ["cs.AI"],
              "keywords": ["agent"],
              "affiliations": ["University X"],
              "pdf_url": "https://arxiv.org/pdf/2604.22001.pdf",
              "abs_url": "https://arxiv.org/abs/2604.22001",
              "code_url": null,
              "project_url": null,
              "doi": null
            },
            {
              "id": "arxiv:2604.22002",
              "source": "arxiv",
              "title": "Sample Two",
              "authors": ["C", "D"],
              "abstract": "Abstract Two",
              "summary_zh": "总结二",
              "tldr": "第二句",
              "recommendation_reason": "推荐理由二",
              "relevance_score": 0.8,
              "published_at": "2026-04-21T00:00:00Z",
              "updated_at": "2026-04-21T01:00:00Z",
              "categories": ["cs.LG"],
              "keywords": ["compression"],
              "affiliations": ["University Y"],
              "pdf_url": "https://arxiv.org/pdf/2604.22002.pdf",
              "abs_url": "https://arxiv.org/abs/2604.22002",
              "code_url": null,
              "project_url": null,
              "doi": null
            }
          ]
        }
        """
        return try! FeedAPIClient().decodeFeed(from: Data(json.utf8))
    }()

    static let emptyFeed: PaperFeed = {
        let json = """
        {
          "schema_version": "1.0",
          "generated_at": "2026-04-23T22:00:00Z",
          "recommendation_date": "2026-04-24",
          "timezone": "Asia/Taipei",
          "source": ["arxiv"],
          "language": "zh-Hans",
          "config": null,
          "stats": {
            "total_candidates": 0,
            "recommended_count": 0,
            "llm_summary_count": 0
          },
          "papers": []
        }
        """
        return try! FeedAPIClient().decodeFeed(from: Data(json.utf8))
    }()

    func fetchLatestFeed(from url: URL) async throws -> PaperFeed {
        Self.sampleFeed
    }

    func decodeFeed(from data: Data) throws -> PaperFeed {
        try FeedAPIClient().decodeFeed(from: data)
    }
}

private struct MockNotificationScheduler: LocalNotificationScheduling {
    func requestAuthorization() async throws {}
    func scheduleDailyReminder(hour: Int, minute: Int) async throws {}
    func cancelDailyReminder() {}
}

private final class MutableMockFeedAPIClient: FeedFetching {
    var feed: PaperFeed

    init(feed: PaperFeed) {
        self.feed = feed
    }

    func fetchLatestFeed(from url: URL) async throws -> PaperFeed {
        feed
    }

    func decodeFeed(from data: Data) throws -> PaperFeed {
        try FeedAPIClient().decodeFeed(from: data)
    }
}
