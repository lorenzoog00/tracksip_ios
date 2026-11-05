import Foundation
import Testing
import UserNotifications
@testable import siptrack

@MainActor
struct WaterReminderTests {
    @Test func refreshingOrRelaunchingPreservesThePendingTimer() async {
        let notifications = TestWaterNotifications()
        let manager = WaterReminderManager(notifications: notifications)
        await manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil).value
        let original = notifications.pending.first
        await manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil).value
        let relaunched = WaterReminderManager(notifications: notifications)
        await relaunched.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil).value
        #expect(notifications.addCount == 1)
        #expect(notifications.pending.first === original)
    }

    @Test func waterIntervalAndNightChangesReplaceTheTimer() async {
        let notifications = TestWaterNotifications()
        let manager = WaterReminderManager(notifications: notifications)
        await manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil).value
        await manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: "glass").value
        #expect(notifications.addCount == 2)
        await manager.schedule(eventId: "night", intervalMinutes: 40, lastWaterEntryId: "glass").value
        #expect(notifications.addCount == 3)
        let trigger = notifications.pending.first?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 2400)
        #expect(trigger?.repeats == true)
        await manager.schedule(eventId: "next-night", intervalMinutes: 40, lastWaterEntryId: nil).value
        #expect(notifications.addCount == 4)
        #expect(notifications.pending.count == 1)
    }

    @Test func disablingAndCancellingRemoveOnlyWaterReminders() async {
        let notifications = TestWaterNotifications()
        let unrelated = UNNotificationRequest(identifier: "weekly-report", content: UNMutableNotificationContent(), trigger: nil)
        notifications.pending = [unrelated]
        let manager = WaterReminderManager(notifications: notifications)
        await manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil).value
        await manager.schedule(eventId: "night", intervalMinutes: nil, lastWaterEntryId: nil).value
        #expect(notifications.pending.map(\.identifier) == ["weekly-report"])
        await manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil).value
        await manager.cancel().value
        #expect(notifications.pending.map(\.identifier) == ["weekly-report"])
    }

    @Test func cancellingDuringAnAddDoesNotLeaveAnOrphanReminder() async {
        let notifications = TestWaterNotifications()
        notifications.pauseNextAdd = true
        let manager = WaterReminderManager(notifications: notifications)
        let scheduled = manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil)
        await notifications.waitForPausedAdd()
        manager.cancel()
        notifications.finishPausedAdd()
        await scheduled.value
        #expect(notifications.pending.isEmpty)
    }

    @Test func waterNotificationsAppearWhileTheAppIsOpen() {
        let options = WaterReminderManager.foregroundOptions(for: "siptrack.water-reminder")
        #expect(options.contains(.banner))
        #expect(options.contains(.list))
        #expect(options.contains(.sound))
        #expect(WaterReminderManager.foregroundOptions(for: "weekly-report").isEmpty)
    }

    @Test func changingSettingsDuringAnAddKeepsOnlyTheLatestInterval() async {
        let notifications = TestWaterNotifications()
        notifications.pauseNextAdd = true
        let manager = WaterReminderManager(notifications: notifications)
        let scheduled = manager.schedule(eventId: "night", intervalMinutes: 25, lastWaterEntryId: nil)
        await notifications.waitForPausedAdd()
        manager.schedule(eventId: "night", intervalMinutes: 40, lastWaterEntryId: nil)
        notifications.finishPausedAdd()
        await scheduled.value
        #expect(notifications.pending.count == 1)
        let trigger = notifications.pending.first?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 2400)
    }
}

@MainActor
private final class TestWaterNotifications: WaterReminderNotifications {
    var pending: [UNNotificationRequest] = []
    var addCount = 0
    var pauseNextAdd = false
    private var pausedAdd: CheckedContinuation<Void, Never>?
    private var addWaiter: CheckedContinuation<Void, Never>?

    func pendingRequests() async -> [UNNotificationRequest] { pending }

    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        if pauseNextAdd {
            pauseNextAdd = false
            await withCheckedContinuation { continuation in
                pausedAdd = continuation
                addWaiter?.resume()
                addWaiter = nil
            }
        }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePending(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func waitForPausedAdd() async {
        guard pausedAdd == nil else { return }
        await withCheckedContinuation { addWaiter = $0 }
    }

    func finishPausedAdd() {
        pausedAdd?.resume()
        pausedAdd = nil
    }
}
