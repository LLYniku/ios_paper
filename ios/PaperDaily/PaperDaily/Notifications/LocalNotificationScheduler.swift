import Foundation
import UserNotifications

enum LocalNotificationError: Error, LocalizedError {
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "通知权限未开启，请在系统设置中允许“每日论文”发送通知。"
        }
    }
}

final class LocalNotificationScheduler: LocalNotificationScheduling {
    private let center: UNUserNotificationCenter
    private let identifier = "paperdaily.daily.reminder"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() async throws {
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        if !granted {
            throw LocalNotificationError.authorizationDenied
        }
    }

    func scheduleDailyReminder(hour: Int, minute: Int) async throws {
        cancelDailyReminder()

        let content = UNMutableNotificationContent()
        content.title = "今日论文推荐"
        content.body = "新的论文推荐可能已经生成，打开 App 查看最新内容。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
