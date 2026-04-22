import Foundation
import XCTest
@testable import PaperDaily

@MainActor
final class PaperStoreTests: XCTestCase {
    func testFavoriteStatePersists() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults)

        store.toggleFavorite("arxiv:2604.22001")

        XCTAssertEqual(Set(defaults.stringArray(forKey: PaperStore.Keys.favoritePaperIDs) ?? []), ["arxiv:2604.22001"])
        XCTAssertTrue(store.isFavorite("arxiv:2604.22001"))
    }

    func testReadStatePersists() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults)

        store.toggleRead("arxiv:2604.22001")

        XCTAssertEqual(Set(defaults.stringArray(forKey: PaperStore.Keys.readPaperIDs) ?? []), ["arxiv:2604.22001"])
        XCTAssertTrue(store.isRead("arxiv:2604.22001"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "PaperStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw XCTSkip("Unable to create isolated defaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(defaults: UserDefaults) -> PaperStore {
        let settings = UserSettingsStore(defaults: defaults)
        let cache = FeedCache(baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return PaperStore(
            apiClient: MockFeedAPIClient(),
            cache: cache,
            settings: settings,
            userDefaults: defaults,
            notificationScheduler: MockNotificationScheduler(),
            sampleFeedLoader: { MockFeedAPIClient.sampleFeed }
        )
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
            "total_candidates": 1,
            "recommended_count": 1,
            "llm_summary_count": 1
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
            }
          ]
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
