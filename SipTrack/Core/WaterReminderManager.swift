import Foundation
import UserNotifications

@MainActor
protocol WaterReminderNotifications {
    func pendingRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePending(withIdentifiers identifiers: [String])
}

@MainActor
private struct SystemWaterReminderNotifications: WaterReminderNotifications {
    func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePending(withIdentifiers identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

@MainActor
final class WaterReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared: WaterReminderManager = {
        let manager = WaterReminderManager(notifications: SystemWaterReminderNotifications())
        UNUserNotificationCenter.current().delegate = manager
        return manager
    }()

    private struct Schedule: Equatable {
        let eventId: String
        let minutes: Int
        let lastWaterEntryId: String
    }

    private let notificationId = "siptrack.water-reminder"
    private let notifications: any WaterReminderNotifications
    private var desiredSchedule: Schedule?
    private var schedulingTask: Task<Void, Never>?

    init(notifications: any WaterReminderNotifications) {
        self.notifications = notifications
        super.init()
    }

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

    @discardableResult
    func schedule(eventId: String, intervalMinutes: Int?, lastWaterEntryId: String?) -> Task<Void, Never> {
        guard let minutes = intervalMinutes, minutes > 0 else { return cancel() }
        return enqueue(Schedule(eventId: eventId, minutes: minutes, lastWaterEntryId: lastWaterEntryId ?? ""))
    }

    @discardableResult
    func cancel() -> Task<Void, Never> {
        notifications.removePending(withIdentifiers: [notificationId])
        return enqueue(nil)
    }

    private func enqueue(_ schedule: Schedule?) -> Task<Void, Never> {
        desiredSchedule = schedule
        if let schedulingTask { return schedulingTask }
        let task = Task {
            await reconcile()
            schedulingTask = nil
        }
        schedulingTask = task
        return task
    }

    // One worker serializes reads, adds, and cancellation. A late add cannot
    // resurrect a reminder after ending the night or switching it off.
    private func reconcile() async {
        while true {
            let schedule = desiredSchedule
            if let schedule {
                let pending = await notifications.pendingRequests()
                guard desiredSchedule == schedule else { continue }
                let existing = pending.first { $0.identifier == notificationId }
                let trigger = existing?.trigger as? UNTimeIntervalNotificationTrigger
                let info = existing?.content.userInfo ?? [:]
                let matches = trigger?.repeats == true
                    && trigger?.timeInterval == Double(schedule.minutes) * 60
                    && (info["eventId"] as? String) == schedule.eventId
                    && (info["lastWaterEntryId"] as? String) == schedule.lastWaterEntryId
                if !matches {
                    let content = UNMutableNotificationContent()
                    content.title = "Hydration check"
                    content.body = "Time for a glass of water! 💧"
                    content.sound = .default
                    content.userInfo = ["eventId": schedule.eventId, "lastWaterEntryId": schedule.lastWaterEntryId]
                    let request = UNNotificationRequest(
                        identifier: notificationId, content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(schedule.minutes) * 60, repeats: true)
                    )
                    do {
                        try await notifications.add(request)
                    } catch {
                        NSLog("Could not schedule water reminder: %@", error.localizedDescription)
                    }
                }
            } else {
                notifications.removePending(withIdentifiers: [notificationId])
            }
            if desiredSchedule == schedule { return }
        }
    }

    nonisolated static func foregroundOptions(for identifier: String) -> UNNotificationPresentationOptions {
        identifier == "siptrack.water-reminder" ? [.banner, .list, .sound] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundOptions(for: notification.request.identifier))
    }
}
