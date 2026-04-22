import Foundation
import Combine

final class UserSettingsStore: ObservableObject {
    static let defaultFeedURLString = "https://llyniku.github.io/ios_paper/data/latest.json"

    enum Keys {
        static let feedURLString = "feedURLString"
        static let notificationsEnabled = "notificationsEnabled"
        static let reminderHour = "reminderHour"
        static let reminderMinute = "reminderMinute"
        static let defaultUnreadOnly = "defaultUnreadOnly"
    }

    @Published var feedURLString: String {
        didSet { defaults.set(feedURLString, forKey: Keys.feedURLString) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Keys.reminderHour) }
    }

    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: Keys.reminderMinute) }
    }

    @Published var defaultUnreadOnly: Bool {
        didSet { defaults.set(defaultUnreadOnly, forKey: Keys.defaultUnreadOnly) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.feedURLString = defaults.string(forKey: Keys.feedURLString) ?? Self.defaultFeedURLString
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        let storedHour = defaults.object(forKey: Keys.reminderHour) as? Int
        let storedMinute = defaults.object(forKey: Keys.reminderMinute) as? Int
        self.reminderHour = storedHour ?? 8
        self.reminderMinute = storedMinute ?? 30
        self.defaultUnreadOnly = defaults.bool(forKey: Keys.defaultUnreadOnly)
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

    var appVersionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
