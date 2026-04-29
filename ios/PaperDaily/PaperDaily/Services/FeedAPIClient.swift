import Foundation

enum FreshFeedRequest {
    static func make(for url: URL) -> URLRequest {
        let requestURL = cacheBustedURL(from: url)
        var request = URLRequest(url: requestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func cacheBustedURL(from url: URL) -> URL {
        guard !url.isFileURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "_paperdaily_refresh" }
        queryItems.append(URLQueryItem(name: "_paperdaily_refresh", value: String(Int(Date().timeIntervalSince1970 * 1000))))
        components.queryItems = queryItems
        return components.url ?? url
    }
}

protocol FeedFetching {
    func fetchLatestFeed(from url: URL) async throws -> PaperFeed
    func decodeFeed(from data: Data) throws -> PaperFeed
}

enum FeedAPIClientError: Error, LocalizedError, Equatable {
    case invalidURL
    case networkError(String)
    case invalidStatusCode(Int)
    case decodingError(String)
    case unsupportedSchemaVersion(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Feed URL 无效。"
        case .networkError(let message):
            return "网络请求失败：\(message)"
        case .invalidStatusCode(let code):
            return "服务端返回了异常状态码：\(code)"
        case .decodingError(let message):
            return "Feed JSON 解析失败：\(message)"
        case .unsupportedSchemaVersion(let version):
            return "暂不支持的 schema 版本：\(version)"
        }
    }
}

final class FeedAPIClient: FeedFetching {
    func fetchLatestFeed(from url: URL) async throws -> PaperFeed {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else {
            throw FeedAPIClientError.invalidURL
        }

        let data: Data
        let response: URLResponse?
        if url.isFileURL {
            do {
                data = try Data(contentsOf: url)
                response = nil
            } catch {
                throw FeedAPIClientError.networkError(error.localizedDescription)
            }
        } else {
            do {
                let result = try await URLSession.shared.data(for: FreshFeedRequest.make(for: url))
                data = result.0
                response = result.1
            } catch {
                throw FeedAPIClientError.networkError(error.localizedDescription)
            }
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw FeedAPIClientError.invalidStatusCode(httpResponse.statusCode)
        }

        return try decodeFeed(from: data)
    }

    func decodeFeed(from data: Data) throws -> PaperFeed {
        do {
            let feed = try FeedCoding.decoder.decode(PaperFeed.self, from: data)
            guard PaperFeed.supportedSchemaVersions.contains(feed.schemaVersion) else {
                throw FeedAPIClientError.unsupportedSchemaVersion(feed.schemaVersion)
            }
            return feed
        } catch let error as FeedAPIClientError {
            throw error
        } catch {
            throw FeedAPIClientError.decodingError(error.localizedDescription)
        }
    }
}
