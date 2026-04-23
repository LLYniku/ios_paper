import Foundation
import Combine

@MainActor
final class UserSettingsStore: ObservableObject {
    static let defaultFeedURLString = SyncDefaults.defaultFeedURLString

    enum Keys {
        static let feedURLString = "feedURLString"
        static let notificationsEnabled = "notificationsEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let defaultUnreadOnly = "defaultUnreadOnly"
        static let syncBaseURLString = "syncBaseURLString"
        static let syncTokenString = "syncTokenString"
    }

    @Published var feedURLString: String {
        didSet {
            guard !isApplyingSyncedPreferences else { return }
            syncStore.updatePreferences { $0.feedURLString = feedURLString }
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            guard !isApplyingSyncedPreferences else { return }
            syncStore.updatePreferences { $0.notificationsEnabled = notificationsEnabled }
        }
    }

    @Published var reminderHour: Int {
        didSet {
            guard !isApplyingSyncedPreferences else { return }
            syncStore.updatePreferences { $0.reminderHour = reminderHour }
        }
    }

    @Published var reminderMinute: Int {
        didSet {
            guard !isApplyingSyncedPreferences else { return }
            syncStore.updatePreferences { $0.reminderMinute = reminderMinute }
        }
    }

    @Published var defaultUnreadOnly: Bool {
        didSet {
            guard !isApplyingSyncedPreferences else { return }
            syncStore.updatePreferences { $0.defaultUnreadOnly = defaultUnreadOnly }
        }
    }

    @Published var syncBaseURLString: String {
        didSet {
            persistLocalSyncSettings()
        }
    }

    @Published var syncTokenString: String {
        didSet {
            persistLocalSyncSettings()
        }
    }

    private let syncStore: AppSyncStore
    private let localDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingSyncedPreferences = false

    init(syncStore: AppSyncStore, localDefaults: UserDefaults = .standard) {
        self.syncStore = syncStore
        self.localDefaults = localDefaults
        let preferences = syncStore.preferences
        self.feedURLString = preferences.feedURLString
        self.notificationsEnabled = preferences.notificationsEnabled
        self.reminderHour = preferences.reminderHour
        self.reminderMinute = preferences.reminderMinute
        self.defaultUnreadOnly = preferences.defaultUnreadOnly
        self.syncBaseURLString = localDefaults.string(forKey: Keys.syncBaseURLString) ?? ""
        self.syncTokenString = localDefaults.string(forKey: Keys.syncTokenString) ?? ""

        syncStore.$preferences
            .receive(on: RunLoop.main)
            .sink { [weak self] preferences in
                self?.apply(preferences)
            }
            .store(in: &cancellables)
    }

    var reminderDate: Date {
        get {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = reminderHour
            components.minute = reminderMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 8
            reminderMinute = components.minute ?? 30
        }
    }

    func updateReminder(date: Date) {
        reminderDate = date
    }

    func resolvedFeedURL() -> URL? {
        let trimmed = feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    func resolvedClassicsURL() -> URL? {
        guard let feedURL = resolvedFeedURL() else { return nil }
        return feedURL.deletingLastPathComponent().appendingPathComponent("classics.json")
    }

    func resolvedNetworkURL() -> URL? {
        guard let feedURL = resolvedFeedURL() else { return nil }
        return feedURL.deletingLastPathComponent().appendingPathComponent("network/latest.json")
    }

    func resolvedSyncConfiguration() -> SyncRemoteConfiguration? {
        let trimmedURL = syncBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = syncTokenString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedToken.isEmpty, let baseURL = URL(string: trimmedURL) else {
            return nil
        }
        return SyncRemoteConfiguration(baseURL: baseURL, token: trimmedToken)
    }

    func applyRemoteSyncInputs() {
        persistLocalSyncSettings()
    }

    var appVersionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func apply(_ preferences: SyncedPreferences) {
        guard feedURLString != preferences.feedURLString
            || notificationsEnabled != preferences.notificationsEnabled
            || reminderHour != preferences.reminderHour
            || reminderMinute != preferences.reminderMinute
            || defaultUnreadOnly != preferences.defaultUnreadOnly
        else {
            return
        }

        isApplyingSyncedPreferences = true
        feedURLString = preferences.feedURLString
        notificationsEnabled = preferences.notificationsEnabled
        reminderHour = preferences.reminderHour
        reminderMinute = preferences.reminderMinute
        defaultUnreadOnly = preferences.defaultUnreadOnly
        isApplyingSyncedPreferences = false
    }

    private func persistLocalSyncSettings() {
        localDefaults.set(syncBaseURLString, forKey: Keys.syncBaseURLString)
        localDefaults.set(syncTokenString, forKey: Keys.syncTokenString)
        syncStore.remoteSyncConfigurationDidChange()
    }
}
