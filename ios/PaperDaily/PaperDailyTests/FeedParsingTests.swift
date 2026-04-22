import XCTest
@testable import PaperDaily

final class FeedParsingTests: XCTestCase {
    func testParsesSampleLatestJSON() throws {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "sample_latest", withExtension: "json"))
        let data = try Data(contentsOf: url)

        let feed = try FeedAPIClient().decodeFeed(from: data)

        XCTAssertEqual(feed.schemaVersion, "1.0")
        XCTAssertFalse(feed.papers.isEmpty)
        XCTAssertEqual(feed.papers.first?.id, "arxiv:2604.22001")
    }

    func testHandlesEmptyPaperList() throws {
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
            "total_candidates": 0,
            "recommended_count": 0,
            "llm_summary_count": 0
          },
          "papers": []
        }
        """

        let feed = try FeedAPIClient().decodeFeed(from: Data(json.utf8))

        XCTAssertEqual(feed.papers.count, 0)
        XCTAssertEqual(feed.stats.recommendedCount, 0)
    }

    func testHandlesMissingOptionalURLs() throws {
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
            "llm_summary_count": 0
          },
          "papers": [
            {
              "id": "arxiv:2604.22003",
              "source": "arxiv",
              "title": "Optional Fields",
              "authors": ["A", "B"],
              "abstract": "Abstract",
              "summary_zh": null,
              "tldr": null,
              "recommendation_reason": null,
              "relevance_score": 0.7,
              "published_at": "2026-04-22T00:00:00Z",
              "updated_at": null,
              "categories": [],
              "keywords": [],
              "affiliations": [],
              "pdf_url": null,
              "abs_url": "https://arxiv.org/abs/2604.22003",
              "code_url": null,
              "project_url": null,
              "doi": null
            }
          ]
        }
        """

        let feed = try FeedAPIClient().decodeFeed(from: Data(json.utf8))

        XCTAssertNil(feed.papers[0].pdfURL)
        XCTAssertNotNil(feed.papers[0].absURL)
    }

    func testInvalidJSONReturnsDecodingError() {
        let client = FeedAPIClient()

        XCTAssertThrowsError(try client.decodeFeed(from: Data("not-json".utf8))) { error in
            guard case .decodingError(let message) = error as? FeedAPIClientError else {
                XCTFail("Expected decodingError, got \(error)")
                return
            }
            XCTAssertFalse(message.isEmpty)
        }
    }
}
