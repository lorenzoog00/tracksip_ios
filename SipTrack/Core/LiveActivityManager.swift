import ActivityKit
import Foundation
import SipTrackActivityKit

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private var activity: Activity<SipTrackActivityAttributes>?
    private init() {}

    func start(eventName: String, eventId: String, quickDrinks: [SipTrackActivityAttributes.QuickDrink]) {
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else {
            #if DEBUG
            print("[LiveActivity] Activities disabled by user in Settings")
            #endif
            return
        }
        end()

        let attrs = SipTrackActivityAttributes(eventName: eventName)
        let state = SipTrackActivityAttributes.ContentState(
            bac: 0,
            drinkCount: 0,
            stageName: "Sober",
            stageColorHex: "#2ED573",
            elapsedMinutes: 0,
            eventId: eventId,
            quickDrinks: quickDrinks,
            startedAt: Date(),
            updatedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
        do {
            activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            #if DEBUG
            let startedId = activity?.id ?? "nil"
            print("[LiveActivity] Started: \(startedId), state: \(String(describing: activity?.activityState))")
            print("[LiveActivity] attributesType: \(String(reflecting: SipTrackActivityAttributes.self))")
            let all = Activity<SipTrackActivityAttributes>.activities
            print("[LiveActivity] Total activities after request: \(all.count)")
            for a in all { print("[LiveActivity]   id=\(a.id) state=\(a.activityState)") }
            #endif
        } catch {
            #if DEBUG
            print("[LiveActivity] Failed to start: \(error)")
            #endif
        }
    }

    /// The running activity. After the app is killed and relaunched the stored
    /// reference is gone while the activity is still on the lock screen, so it is
    /// re-attached from the system list; without this every update after a
    /// relaunch was dropped and the lock screen froze.
    private func currentActivity() -> Activity<SipTrackActivityAttributes>? {
        if let activity, activity.activityState == .active || activity.activityState == .stale {
            return activity
        }
        activity = Activity<SipTrackActivityAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }
        return activity
    }

    func update(bac: Double, drinkCount: Int, stageName: String, stageColorHex: String, elapsedMinutes: Int, safeToDriveAt: Date?, soberAt: Date?, startedAt: Date?) {
        guard let activity = currentActivity() else { return }
        let state = SipTrackActivityAttributes.ContentState(
            bac: bac,
            drinkCount: drinkCount,
            stageName: stageName,
            stageColorHex: stageColorHex,
            elapsedMinutes: elapsedMinutes,
            eventId: activity.content.state.eventId,
            quickDrinks: activity.content.state.quickDrinks,
            safeToDriveAt: safeToDriveAt,
            soberAt: soberAt,
            startedAt: startedAt,
            updatedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
        Task { await activity.update(content) }
    }

    func end() {
        // End every SipTrack activity, including one left over from before a
        // relaunch that this instance never held a reference to.
        let all = Activity<SipTrackActivityAttributes>.activities
        for a in all {
            let content = ActivityContent(state: a.content.state, staleDate: nil)
            Task { await a.end(content, dismissalPolicy: .immediate) }
        }
        self.activity = nil
    }

}
