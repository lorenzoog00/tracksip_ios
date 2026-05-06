import UserNotifications

@MainActor
final class WaterReminderManager {
    static let shared = WaterReminderManager()
    private let notificationId = "siptrack.water-reminder"
    private init() {}

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .denied: return false
        default:
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            return granted ?? false
        }
    }

    func schedule(intervalMinutes: Int?) {
        guard let minutes = intervalMinutes, minutes > 0 else { cancel(); return }
        let content = UNMutableNotificationContent()
        content.title = "Hydration check"
        content.body = "Time for a glass of water! 💧"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(minutes) * 60,
            repeats: false
        )
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
    }
}
