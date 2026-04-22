import Foundation

final class NetworkFeedCache {
    private let fileManager: FileManager
    private let baseDirectory: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PaperDaily", isDirectory: true)
        }
    }

    func save(_ feed: NetworkFeed) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try FeedCoding.encoder.encode(feed)
        try data.write(to: cacheFileURL, options: [.atomic])
    }

    func load() throws -> NetworkFeed? {
        guard fileManager.fileExists(atPath: cacheFileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: cacheFileURL)
        return try FeedCoding.decoder.decode(NetworkFeed.self, from: data)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: cacheFileURL.path) else {
            return
        }
        try fileManager.removeItem(at: cacheFileURL)
    }

    private var cacheFileURL: URL {
        baseDirectory.appendingPathComponent("network_feed.json")
    }
}
