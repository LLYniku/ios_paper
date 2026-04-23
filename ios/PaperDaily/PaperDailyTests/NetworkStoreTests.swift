import Foundation
import XCTest
@testable import PaperDaily

@MainActor
final class NetworkStoreTests: XCTestCase {
    func testNetworkCardsPreferTLDR() throws {
        let feed = MockNetworkFeedAPIClient.sampleFeed

        XCTAssertEqual(feed.items.first?.displaySummary, "一条关于高效推理与 KV Cache 优化的 GitHub 仓库。")
    }

    func testFavoriteNetworkPersistsAcrossRefreshes() async throws {
        let defaults = try makeDefaults()
        let apiClient = MutableMockNetworkFeedAPIClient(feed: MockNetworkFeedAPIClient.sampleFeed)
        let store = makeStore(defaults: defaults, apiClient: apiClient)

        await store.bootstrap()
        let item = try XCTUnwrap(store.feed?.items.first)
        store.toggleFavorite(item)

        apiClient.feed = MockNetworkFeedAPIClient.olderFeed
        await store.refresh()

        let favorites = store.favoriteItems()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.item.id, item.id)
        XCTAssertTrue(store.isFavorite(item.id))
    }

    func testReadNetworkPersists() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults)

        await store.bootstrap()
        let itemID = try XCTUnwrap(store.feed?.items.first?.id)
        store.toggleRead(itemID)

        XCTAssertTrue(store.isRead(itemID))
        XCTAssertEqual(Set(defaults.stringArray(forKey: NetworkStore.Keys.readNetworkIDs) ?? []), [itemID])
    }

    func testFavoriteNetworkRatingPersistsAndSortsHigherFirst() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults)

        await store.bootstrap()
        let items = try XCTUnwrap(store.feed?.items)
        store.toggleFavorite(items[0])
        store.toggleFavorite(items[1])
        store.setFavoriteRating(items[1].id, rating: 4)
        store.setFavoriteRating(items[0].id, rating: 1)

        let favorites = store.favoriteItems()
        XCTAssertEqual(favorites.map(\.id), [items[1].id, items[0].id])
        XCTAssertEqual(favorites.map(\.rating), [4, 1])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "NetworkStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(
        defaults: UserDefaults,
        apiClient: NetworkFeedFetching = MockNetworkFeedAPIClient()
    ) -> NetworkStore {
        let settings = UserSettingsStore(defaults: defaults)
        let cache = NetworkFeedCache(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return NetworkStore(
            settings: settings,
            apiClient: apiClient,
            cache: cache,
            userDefaults: defaults,
            sampleFeedLoader: { MockNetworkFeedAPIClient.sampleFeed }
        )
    }
}

private struct MockNetworkFeedAPIClient: NetworkFeedFetching {
    static let sampleFeed: NetworkFeed = {
        let json = """
        {
          "schema_version": "1.0",
          "generated_at": "2026-04-22T22:00:00Z",
          "recommendation_date": "2026-04-22",
          "timezone": "Asia/Shanghai",
          "language": "zh-Hans",
          "config": {
            "max_item_num": 30,
            "summary_top_n": 20,
            "platforms": ["github", "openreview"]
          },
          "stats": {
            "total_candidates": 20,
            "recommended_count": 2,
            "llm_summary_count": 2
          },
          "items": [
            {
              "id": "github:streamingllm",
              "platform": "github",
              "content_type": "repository",
              "title": "streaming-llm",
              "creator": "mit-han-lab",
              "source_label": "mit-han-lab/streaming-llm",
              "published_at": "2026-04-22T08:00:00Z",
              "url": "https://github.com/mit-han-lab/streaming-llm",
              "raw_excerpt": "English excerpt",
              "summary_zh": "一个关于长上下文推理优化的仓库。",
              "tldr": "一条关于高效推理与 KV Cache 优化的 GitHub 仓库。",
              "recommendation_reason": "和推理优化很接近。",
              "relevance_score": 0.92,
              "tags": ["kv-cache", "llm"],
              "thumbnail_url": null,
              "venue": null,
              "year": 2026
            },
            {
              "id": "openreview:paper1",
              "platform": "openreview",
              "content_type": "paper",
              "title": "Adaptive KV Budgeting",
              "creator": "Ada Zhang",
              "source_label": "ICLR.cc/2026/Conference",
              "published_at": "2026-04-20T08:00:00Z",
              "url": "https://openreview.net/forum?id=paper1",
              "raw_excerpt": "English excerpt",
              "summary_zh": "一篇关于 KV Cache 预算分配的论文。",
              "tldr": "一篇研究缓存预算分配的 OpenReview 论文。",
              "recommendation_reason": "和缓存压缩相关。",
              "relevance_score": 0.89,
              "tags": ["cache", "efficiency"],
              "thumbnail_url": null,
              "venue": "ICLR.cc/2026/Conference",
              "year": 2026
            }
          ]
        }
        """
        return try! NetworkFeedAPIClient().decodeFeed(from: Data(json.utf8))
    }()

    static let olderFeed: NetworkFeed = {
        let json = """
        {
          "schema_version": "1.0",
          "generated_at": "2026-04-20T22:00:00Z",
          "recommendation_date": "2026-04-20",
          "timezone": "Asia/Shanghai",
          "language": "zh-Hans",
          "config": {
            "max_item_num": 30,
            "summary_top_n": 20,
            "platforms": ["openreview"]
          },
          "stats": {
            "total_candidates": 10,
            "recommended_count": 1,
            "llm_summary_count": 1
          },
          "items": [
            {
              "id": "openreview:paper1",
              "platform": "openreview",
              "content_type": "paper",
              "title": "Adaptive KV Budgeting",
              "creator": "Ada Zhang",
              "source_label": "ICLR.cc/2026/Conference",
              "published_at": "2026-04-20T08:00:00Z",
              "url": "https://openreview.net/forum?id=paper1",
              "raw_excerpt": "English excerpt",
              "summary_zh": "一篇关于 KV Cache 预算分配的论文。",
              "tldr": "一篇研究缓存预算分配的 OpenReview 论文。",
              "recommendation_reason": "和缓存压缩相关。",
              "relevance_score": 0.89,
              "tags": ["cache", "efficiency"],
              "thumbnail_url": null,
              "venue": "ICLR.cc/2026/Conference",
              "year": 2026
            }
          ]
        }
        """
        return try! NetworkFeedAPIClient().decodeFeed(from: Data(json.utf8))
    }()

    func fetchFeed(from url: URL) async throws -> NetworkFeed {
        Self.sampleFeed
    }

    func decodeFeed(from data: Data) throws -> NetworkFeed {
        try NetworkFeedAPIClient().decodeFeed(from: data)
    }
}

private final class MutableMockNetworkFeedAPIClient: NetworkFeedFetching {
    var feed: NetworkFeed

    init(feed: NetworkFeed) {
        self.feed = feed
    }

    func fetchFeed(from url: URL) async throws -> NetworkFeed {
        feed
    }

    func decodeFeed(from data: Data) throws -> NetworkFeed {
        try NetworkFeedAPIClient().decodeFeed(from: data)
    }
}
