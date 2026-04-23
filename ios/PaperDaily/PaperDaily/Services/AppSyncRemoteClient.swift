import Foundation

enum AppSyncRemoteClientError: LocalizedError {
    case invalidConfiguration
    case unauthorized
    case invalidStatusCode(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "同步配置无效。"
        case .unauthorized:
            return "同步 token 无效或未授权。"
        case let .invalidStatusCode(code):
            return "同步服务返回异常状态码：\(code)"
        case .decodingFailed:
            return "同步服务返回了无法解析的数据。"
        }
    }
}

protocol AppSyncRemoteServing {
    func fetchSnapshot(configuration: SyncRemoteConfiguration) async throws -> SyncedStateSnapshot?
    func mergeSnapshot(
        _ snapshot: SyncedStateSnapshot,
        configuration: SyncRemoteConfiguration
    ) async throws -> SyncedStateSnapshot
}

struct AppSyncRemoteClient: AppSyncRemoteServing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSnapshot(configuration: SyncRemoteConfiguration) async throws -> SyncedStateSnapshot? {
        let request = try makeRequest(
            url: configuration.baseURL.appendingPathComponent("v1/state"),
            token: configuration.token
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        struct Response: Codable {
            let state: SyncedStateSnapshot?
        }

        guard let decoded = try? FeedCoding.decoder.decode(Response.self, from: data) else {
            throw AppSyncRemoteClientError.decodingFailed
        }
        return decoded.state
    }

    func mergeSnapshot(
        _ snapshot: SyncedStateSnapshot,
        configuration: SyncRemoteConfiguration
    ) async throws -> SyncedStateSnapshot {
        var request = try makeRequest(
            url: configuration.baseURL.appendingPathComponent("v1/state/merge"),
            token: configuration.token
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try FeedCoding.encoder.encode(snapshot)

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        struct Response: Codable {
            let state: SyncedStateSnapshot
        }

        guard let decoded = try? FeedCoding.decoder.decode(Response.self, from: data) else {
            throw AppSyncRemoteClientError.decodingFailed
        }
        return decoded.state
    }

    private func makeRequest(url: URL, token: String) throws -> URLRequest {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppSyncRemoteClientError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppSyncRemoteClientError.invalidStatusCode(-1)
        }

        switch httpResponse.statusCode {
        case 200:
            return
        case 401, 403:
            throw AppSyncRemoteClientError.unauthorized
        default:
            throw AppSyncRemoteClientError.invalidStatusCode(httpResponse.statusCode)
        }
    }
}
