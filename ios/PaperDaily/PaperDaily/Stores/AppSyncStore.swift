import Foundation
import Combine

@MainActor
final class AppSyncStore: ObservableObject {
    enum Keys {
        static let preferences = "synced.preferences"
        static let paperFavorites = "synced.paperFavorites"
        static let paperReadIDs = "synced.paperReadIDs"
        static let classicFavorites = "synced.classicFavorites"
        static let classicReadIDs = "synced.classicReadIDs"
        static let networkFavorites = "synced.networkFavorites"
        static let networkReadIDs = "synced.networkReadIDs"
        static let recentOpens = "synced.recentOpens"
    }

    @Published private(set) var preferences: SyncedPreferences
    @Published private(set) var paperFavoriteRecords: [FavoritePaperRecord]
    @Published private(set) var paperReadIDs: Set<String>
    @Published private(set) var classicFavoriteRecords: [FavoriteClassicRecord]
    @Published private(set) var classicReadIDs: Set<String>
    @Published private(set) var networkFavoriteRecords: [FavoriteNetworkRecord]
    @Published private(set) var networkReadIDs: Set<String>
    @Published private(set) var recentOpenEntries: [RecentOpenEntry]
    @Published private(set) var cloudSyncEnabled: Bool
    @Published private(set) var cloudAccountAvailable: Bool
    @Published private(set) var remoteSyncEnabled: Bool
    @Published private(set) var remoteSyncStatus: String?

    private let defaults: UserDefaults
    private let cloudStore: NSUbiquitousKeyValueStore?
    private let remoteClient: AppSyncRemoteServing
    private var didStart = false
    private var externalChangeCancellable: AnyCancellable?
    private var remoteConfigurationProvider: (() -> SyncRemoteConfiguration?)?
    private var remoteSyncTask: Task<Void, Never>?
    private var remotePollingTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        cloudStore: NSUbiquitousKeyValueStore? = nil,
        remoteClient: AppSyncRemoteServing = AppSyncRemoteClient()
    ) {
        self.defaults = defaults
        self.cloudStore = cloudStore
        self.remoteClient = remoteClient

        self.preferences = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.preferences),
            as: SyncedPreferences.self
        )?.value ?? SyncedPreferences.default
        self.paperFavoriteRecords = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.paperFavorites),
            as: [FavoritePaperRecord].self
        )?.value ?? []
        self.paperReadIDs = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.paperReadIDs),
            as: Set<String>.self
        )?.value ?? []
        self.classicFavoriteRecords = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.classicFavorites),
            as: [FavoriteClassicRecord].self
        )?.value ?? []
        self.classicReadIDs = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.classicReadIDs),
            as: Set<String>.self
        )?.value ?? []
        self.networkFavoriteRecords = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.networkFavorites),
            as: [FavoriteNetworkRecord].self
        )?.value ?? []
        self.networkReadIDs = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.networkReadIDs),
            as: Set<String>.self
        )?.value ?? []
        self.recentOpenEntries = Self.decodeEnvelope(
            from: defaults.data(forKey: Keys.recentOpens),
            as: [RecentOpenEntry].self
        )?.value ?? []
        self.cloudSyncEnabled = cloudStore != nil
        self.cloudAccountAvailable = FileManager.default.ubiquityIdentityToken != nil
        self.remoteSyncEnabled = false
        self.remoteSyncStatus = nil
    }

    func configureRemote(_ provider: @escaping () -> SyncRemoteConfiguration?) {
        remoteConfigurationProvider = provider
        refreshRemoteConfigurationState()
        refreshRemotePolling()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        refreshCloudAccountAvailability()
        refreshRemoteConfigurationState()
        refreshRemotePolling()
        migrateLegacyLocalStateIfNeeded()
        reconcileAllKeys()

        if let cloudStore {
            externalChangeCancellable = NotificationCenter.default
                .publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloudStore)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshFromCloud()
                    }
                }

            cloudStore.synchronize()
        }
    }

    func refreshFromCloud() {
        refreshCloudAccountAvailability()
        refreshRemoteConfigurationState()
        guard let cloudStore else {
            reconcileAllKeys()
            return
        }
        cloudStore.synchronize()
        reconcileAllKeys()
    }

    func refreshFromRemote() {
        refreshRemoteConfigurationState()
        guard let configuration = remoteConfigurationProvider?() else {
            remoteSyncStatus = "请先填写有效的 Worker URL 和 Sync Token。"
            return
        }
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { [weak self] in
            await self?.pullRemoteSnapshot(configuration: configuration)
        }
    }

    func pushToRemote() {
        refreshRemoteConfigurationState()
        guard let configuration = remoteConfigurationProvider?() else {
            remoteSyncStatus = "请先填写有效的 Worker URL 和 Sync Token。"
            return
        }
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { [weak self] in
            await self?.pushLocalSnapshot(configuration: configuration)
        }
    }

    func remoteSyncConfigurationDidChange() {
        refreshRemoteConfigurationState()
        guard remoteConfigurationProvider?() != nil else {
            remoteSyncStatus = "远端同步未配置。"
            refreshRemotePolling()
            return
        }
        refreshRemotePolling()
        refreshFromRemote()
    }

    func updatePreferences(_ update: (inout SyncedPreferences) -> Void) {
        var next = preferences
        update(&next)
        write(next, forKey: Keys.preferences)
        preferences = next
    }

    func setPaperFavoriteRecords(_ records: [FavoritePaperRecord]) {
        let normalized = records.sorted(by: paperFavoriteSort)
        write(normalized, forKey: Keys.paperFavorites)
        paperFavoriteRecords = normalized
    }

    func setPaperReadIDs(_ ids: Set<String>) {
        write(ids, forKey: Keys.paperReadIDs)
        paperReadIDs = ids
    }

    func setClassicFavoriteRecords(_ records: [FavoriteClassicRecord]) {
        let normalized = records.sorted(by: classicFavoriteSort)
        write(normalized, forKey: Keys.classicFavorites)
        classicFavoriteRecords = normalized
    }

    func setClassicReadIDs(_ ids: Set<String>) {
        write(ids, forKey: Keys.classicReadIDs)
        classicReadIDs = ids
    }

    func setNetworkFavoriteRecords(_ records: [FavoriteNetworkRecord]) {
        let normalized = records.sorted(by: networkFavoriteSort)
        write(normalized, forKey: Keys.networkFavorites)
        networkFavoriteRecords = normalized
    }

    func setNetworkReadIDs(_ ids: Set<String>) {
        write(ids, forKey: Keys.networkReadIDs)
        networkReadIDs = ids
    }

    func recordOpen(
        kind: SyncedContentKind,
        itemID: String,
        title: String,
        subtitle: String,
        url: URL?
    ) {
        let nextEntry = RecentOpenEntry(
            kind: kind,
            itemID: itemID,
            title: title,
            subtitle: subtitle,
            urlString: url?.absoluteString,
            openedAt: Date()
        )
        var nextEntries = recentOpenEntries.filter { $0.id != nextEntry.id }
        nextEntries.insert(nextEntry, at: 0)
        if nextEntries.count > 40 {
            nextEntries = Array(nextEntries.prefix(40))
        }
        write(nextEntries, forKey: Keys.recentOpens)
        recentOpenEntries = nextEntries
    }

    private func reconcileAllKeys() {
        preferences = resolveValue(forKey: Keys.preferences, fallback: SyncedPreferences.default)
        paperFavoriteRecords = resolveValue(forKey: Keys.paperFavorites, fallback: [])
        paperReadIDs = resolveValue(forKey: Keys.paperReadIDs, fallback: [])
        classicFavoriteRecords = resolveValue(forKey: Keys.classicFavorites, fallback: [])
        classicReadIDs = resolveValue(forKey: Keys.classicReadIDs, fallback: [])
        networkFavoriteRecords = resolveValue(forKey: Keys.networkFavorites, fallback: [])
        networkReadIDs = resolveValue(forKey: Keys.networkReadIDs, fallback: [])
        recentOpenEntries = resolveValue(forKey: Keys.recentOpens, fallback: [])
    }

    private func resolveValue<Value: Codable>(forKey key: String, fallback: Value) -> Value {
        let localEnvelope: SyncedEnvelope<Value>? = readEnvelope(forKey: key, from: defaults)
        let cloudEnvelope: SyncedEnvelope<Value>? = cloudStore.flatMap {
            readEnvelope(forKey: key, from: $0)
        }

        let chosen: SyncedEnvelope<Value>
        switch (localEnvelope, cloudEnvelope) {
        case let (.some(local), .some(cloud)):
            chosen = local.updatedAt >= cloud.updatedAt ? local : cloud
        case let (.some(local), .none):
            chosen = local
        case let (.none, .some(cloud)):
            chosen = cloud
        case (.none, .none):
            let fresh = SyncedEnvelope(updatedAt: Date(), value: fallback)
            persistEnvelope(fresh, forKey: key)
            return fallback
        }

        persistEnvelope(chosen, forKey: key)
        return chosen.value
    }

    private func write<Value: Codable>(_ value: Value, forKey key: String) {
        let envelope = SyncedEnvelope(updatedAt: Date(), value: value)
        persistEnvelope(envelope, forKey: key)
        cloudStore?.synchronize()
        scheduleRemoteMerge()
    }

    private func persistEnvelope<Value: Codable>(_ envelope: SyncedEnvelope<Value>, forKey key: String) {
        guard let data = try? FeedCoding.encoder.encode(envelope) else { return }
        defaults.set(data, forKey: key)
        cloudStore?.set(data, forKey: key)
    }

    private func readEnvelope<Value: Codable>(forKey key: String, from defaults: UserDefaults) -> SyncedEnvelope<Value>? {
        Self.decodeEnvelope(from: defaults.data(forKey: key), as: Value.self)
    }

    private func readEnvelope<Value: Codable>(forKey key: String, from cloudStore: NSUbiquitousKeyValueStore) -> SyncedEnvelope<Value>? {
        Self.decodeEnvelope(from: cloudStore.object(forKey: key) as? Data, as: Value.self)
    }

    private func migrateLegacyLocalStateIfNeeded() {
        if defaults.data(forKey: Keys.preferences) == nil {
            let notificationsEnabled = defaults.bool(forKey: UserSettingsStore.Keys.notificationsEnabled)
            let reminderHour = defaults.object(forKey: UserSettingsStore.Keys.reminderHour) as? Int ?? 8
            let reminderMinute = defaults.object(forKey: UserSettingsStore.Keys.reminderMinute) as? Int ?? 30
            let defaultUnreadOnly = defaults.bool(forKey: UserSettingsStore.Keys.defaultUnreadOnly)
            let feedURLString = defaults.string(forKey: UserSettingsStore.Keys.feedURLString) ?? SyncedPreferences.default.feedURLString
            let migrated = SyncedPreferences(
                feedURLString: feedURLString,
                notificationsEnabled: notificationsEnabled,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                defaultUnreadOnly: defaultUnreadOnly
            )
            write(migrated, forKey: Keys.preferences)
        }

        if defaults.data(forKey: Keys.paperFavorites) == nil {
            let migrated = decodeLegacy([FavoritePaperRecord].self, key: PaperStore.Keys.favoritePaperRecords) ?? []
            write(migrated, forKey: Keys.paperFavorites)
        }
        if defaults.data(forKey: Keys.paperReadIDs) == nil {
            let migrated = Set(defaults.stringArray(forKey: PaperStore.Keys.readPaperIDs) ?? [])
            write(migrated, forKey: Keys.paperReadIDs)
        }
        if defaults.data(forKey: Keys.classicFavorites) == nil {
            let migrated = decodeLegacy([FavoriteClassicRecord].self, key: ClassicsStore.Keys.favoriteClassicRecords) ?? []
            write(migrated, forKey: Keys.classicFavorites)
        }
        if defaults.data(forKey: Keys.classicReadIDs) == nil {
            let migrated = Set(defaults.stringArray(forKey: ClassicsStore.Keys.readClassicIDs) ?? [])
            write(migrated, forKey: Keys.classicReadIDs)
        }
        if defaults.data(forKey: Keys.networkFavorites) == nil {
            let migrated = decodeLegacy([FavoriteNetworkRecord].self, key: NetworkStore.Keys.favoriteNetworkRecords) ?? []
            write(migrated, forKey: Keys.networkFavorites)
        }
        if defaults.data(forKey: Keys.networkReadIDs) == nil {
            let migrated = Set(defaults.stringArray(forKey: NetworkStore.Keys.readNetworkIDs) ?? [])
            write(migrated, forKey: Keys.networkReadIDs)
        }
        if defaults.data(forKey: Keys.recentOpens) == nil {
            write([RecentOpenEntry](), forKey: Keys.recentOpens)
        }
    }

    private func decodeLegacy<Value: Codable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? FeedCoding.decoder.decode(type, from: data)
    }

    private func refreshCloudAccountAvailability() {
        cloudAccountAvailable = FileManager.default.ubiquityIdentityToken != nil
    }

    private func refreshRemoteConfigurationState() {
        remoteSyncEnabled = remoteConfigurationProvider?() != nil
    }

    private func refreshRemotePolling() {
        remotePollingTask?.cancel()
        guard remoteConfigurationProvider?() != nil else { return }
        remotePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.refreshFromRemote()
                }
            }
        }
    }

    private func scheduleRemoteMerge() {
        refreshRemoteConfigurationState()
        guard let configuration = remoteConfigurationProvider?() else { return }
        remoteSyncTask?.cancel()
        remoteSyncTask = Task { [weak self] in
            await self?.pushLocalSnapshot(configuration: configuration)
        }
    }

    private func pushLocalSnapshot(configuration: SyncRemoteConfiguration) async {
        let snapshot = currentSnapshot()
        do {
            let merged = try await remoteClient.mergeSnapshot(snapshot, configuration: configuration)
            apply(snapshot: merged)
            remoteSyncStatus = "远端同步已更新。"
        } catch {
            remoteSyncStatus = error.localizedDescription
        }
    }

    private func pullRemoteSnapshot(configuration: SyncRemoteConfiguration) async {
        do {
            if let snapshot = try await remoteClient.fetchSnapshot(configuration: configuration) {
                apply(snapshot: snapshot)
                remoteSyncStatus = "已从远端拉取同步状态。"
            } else {
                remoteSyncStatus = "远端暂无同步数据。"
            }
        } catch {
            remoteSyncStatus = error.localizedDescription
        }
    }

    private func currentSnapshot() -> SyncedStateSnapshot {
        SyncedStateSnapshot(
            schemaVersion: SyncedStateSnapshot.currentSchemaVersion,
            preferences: currentEnvelope(forKey: Keys.preferences, fallback: SyncedPreferences.default),
            paperFavoriteRecords: currentEnvelope(forKey: Keys.paperFavorites, fallback: []),
            paperReadIDs: currentEnvelope(forKey: Keys.paperReadIDs, fallback: []),
            classicFavoriteRecords: currentEnvelope(forKey: Keys.classicFavorites, fallback: []),
            classicReadIDs: currentEnvelope(forKey: Keys.classicReadIDs, fallback: []),
            networkFavoriteRecords: currentEnvelope(forKey: Keys.networkFavorites, fallback: []),
            networkReadIDs: currentEnvelope(forKey: Keys.networkReadIDs, fallback: []),
            recentOpenEntries: currentEnvelope(forKey: Keys.recentOpens, fallback: [])
        )
    }

    private func currentEnvelope<Value: Codable>(forKey key: String, fallback: Value) -> SyncedEnvelope<Value> {
        if let envelope: SyncedEnvelope<Value> = readEnvelope(forKey: key, from: defaults) {
            return envelope
        }
        let fresh = SyncedEnvelope(updatedAt: Date(), value: fallback)
        persistEnvelope(fresh, forKey: key)
        return fresh
    }

    private func apply(snapshot: SyncedStateSnapshot) {
        persistEnvelope(snapshot.preferences, forKey: Keys.preferences)
        persistEnvelope(snapshot.paperFavoriteRecords, forKey: Keys.paperFavorites)
        persistEnvelope(snapshot.paperReadIDs, forKey: Keys.paperReadIDs)
        persistEnvelope(snapshot.classicFavoriteRecords, forKey: Keys.classicFavorites)
        persistEnvelope(snapshot.classicReadIDs, forKey: Keys.classicReadIDs)
        persistEnvelope(snapshot.networkFavoriteRecords, forKey: Keys.networkFavorites)
        persistEnvelope(snapshot.networkReadIDs, forKey: Keys.networkReadIDs)
        persistEnvelope(snapshot.recentOpenEntries, forKey: Keys.recentOpens)
        reconcileAllKeys()
    }

    private static func decodeEnvelope<Value: Codable>(from data: Data?, as: Value.Type) -> SyncedEnvelope<Value>? {
        guard let data else { return nil }
        return try? FeedCoding.decoder.decode(SyncedEnvelope<Value>.self, from: data)
    }

    private func paperFavoriteSort(lhs: FavoritePaperRecord, rhs: FavoritePaperRecord) -> Bool {
        if lhs.rating != rhs.rating {
            return lhs.rating > rhs.rating
        }
        if lhs.recommendationDate != rhs.recommendationDate {
            return lhs.recommendationDate > rhs.recommendationDate
        }
        if lhs.favoritedAt != rhs.favoritedAt {
            return lhs.favoritedAt > rhs.favoritedAt
        }
        return lhs.paper.title.localizedCaseInsensitiveCompare(rhs.paper.title) == .orderedAscending
    }

    private func classicFavoriteSort(lhs: FavoriteClassicRecord, rhs: FavoriteClassicRecord) -> Bool {
        if lhs.rating != rhs.rating {
            return lhs.rating > rhs.rating
        }
        if lhs.paper.year != rhs.paper.year {
            return (lhs.paper.year ?? Int.min) > (rhs.paper.year ?? Int.min)
        }
        if lhs.favoritedAt != rhs.favoritedAt {
            return lhs.favoritedAt > rhs.favoritedAt
        }
        return lhs.paper.title.localizedCaseInsensitiveCompare(rhs.paper.title) == .orderedAscending
    }

    private func networkFavoriteSort(lhs: FavoriteNetworkRecord, rhs: FavoriteNetworkRecord) -> Bool {
        if lhs.rating != rhs.rating {
            return lhs.rating > rhs.rating
        }
        if lhs.recommendationDate != rhs.recommendationDate {
            return lhs.recommendationDate > rhs.recommendationDate
        }
        if lhs.favoritedAt != rhs.favoritedAt {
            return lhs.favoritedAt > rhs.favoritedAt
        }
        return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
    }
}
