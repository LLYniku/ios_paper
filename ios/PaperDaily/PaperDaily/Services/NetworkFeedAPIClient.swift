import Foundation

protocol NetworkFeedFetching {
    func fetchFeed(from url: URL) async throws -> NetworkFeed
    func decodeFeed(from data: Data) throws -> NetworkFeed
}

enum NetworkFeedAPIClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case networkError(String)
    case invalidStatusCode(Int)
    case decodingError(String)
    case unsupportedSchemaVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "网络内容数据源 URL 无效。"
        case .networkError(let message):
            return "网络内容请求失败：\(message)"
        case .invalidStatusCode(let code):
            return "网络内容服务端返回了异常状态码：\(code)"
        case .decodingError(let message):
            return "网络内容 JSON 解析失败：\(message)"
        case .unsupportedSchemaVersion(let version):
            return "网络内容 schema 版本不支持：\(version)"
        }
    }
}

final class NetworkFeedAPIClient: NetworkFeedFetching {
    func fetchFeed(from url: URL) async throws -> NetworkFeed {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else {
            throw NetworkFeedAPIClientError.invalidURL
        }

        let data: Data
        let response: URLResponse?
        if url.isFileURL {
            do {
                data = try Data(contentsOf: url)
                response = nil
            } catch {
                throw NetworkFeedAPIClientError.networkError(error.localizedDescription)
            }
        } else {
            do {
                let result = try await URLSession.shared.data(for: FreshFeedRequest.make(for: url))
                data = result.0
                response = result.1
            } catch {
                throw NetworkFeedAPIClientError.networkError(error.localizedDescription)
            }
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw NetworkFeedAPIClientError.invalidStatusCode(httpResponse.statusCode)
        }

        return try decodeFeed(from: data)
    }

    func decodeFeed(from data: Data) throws -> NetworkFeed {
        do {
            let feed = try FeedCoding.decoder.decode(NetworkFeed.self, from: data)
            guard NetworkFeed.supportedSchemaVersions.contains(feed.schemaVersion) else {
                throw NetworkFeedAPIClientError.unsupportedSchemaVersion(feed.schemaVersion)
            }
            return feed
        } catch let error as NetworkFeedAPIClientError {
            throw error
        } catch {
            throw NetworkFeedAPIClientError.decodingError(error.localizedDescription)
        }
    }
}
