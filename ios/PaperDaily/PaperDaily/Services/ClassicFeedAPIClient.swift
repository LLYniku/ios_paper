import Foundation

protocol ClassicsFeedFetching {
    func fetchFeed(from url: URL) async throws -> ClassicsFeed
    func decodeFeed(from data: Data) throws -> ClassicsFeed
}

enum ClassicFeedAPIClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case networkError(String)
    case invalidStatusCode(Int)
    case decodingError(String)
    case unsupportedSchemaVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "经典论文数据源 URL 无效。"
        case .networkError(let message):
            return "经典论文网络请求失败：\(message)"
        case .invalidStatusCode(let code):
            return "经典论文服务端返回了异常状态码：\(code)"
        case .decodingError(let message):
            return "经典论文 JSON 解析失败：\(message)"
        case .unsupportedSchemaVersion(let version):
            return "经典论文 schema 版本不支持：\(version)"
        }
    }
}

final class ClassicFeedAPIClient: ClassicsFeedFetching {
    func fetchFeed(from url: URL) async throws -> ClassicsFeed {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else {
            throw ClassicFeedAPIClientError.invalidURL
        }

        let data: Data
        let response: URLResponse?
        if url.isFileURL {
            do {
                data = try Data(contentsOf: url)
                response = nil
            } catch {
                throw ClassicFeedAPIClientError.networkError(error.localizedDescription)
            }
        } else {
            do {
                let result = try await URLSession.shared.data(for: FreshFeedRequest.make(for: url))
                data = result.0
                response = result.1
            } catch {
                throw ClassicFeedAPIClientError.networkError(error.localizedDescription)
            }
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw ClassicFeedAPIClientError.invalidStatusCode(httpResponse.statusCode)
        }

        return try decodeFeed(from: data)
    }

    func decodeFeed(from data: Data) throws -> ClassicsFeed {
        do {
            let feed = try FeedCoding.decoder.decode(ClassicsFeed.self, from: data)
            guard ClassicsFeed.supportedSchemaVersions.contains(feed.schemaVersion) else {
                throw ClassicFeedAPIClientError.unsupportedSchemaVersion(feed.schemaVersion)
            }
            return feed
        } catch let error as ClassicFeedAPIClientError {
            throw error
        } catch {
            throw ClassicFeedAPIClientError.decodingError(error.localizedDescription)
        }
    }
}
