import ActivityKit
import Foundation
import SipTrackActivityKit

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private var activity: Activity<SipTrackActivityAttributes>?
    private var stateMonitorTask: Task<Void, Never>?
    private init() {}

    func start(eventName: String, eventId: String, quickDrinks: [SipTrackActivityAttributes.QuickDrink]) {
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else {
            print("[LiveActivity] Activities disabled by user in Settings")
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
            quickDrinks: quickDrinks
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
        do {
            activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            let startedId = activity?.id ?? "nil"
            print("[LiveActivity] Started: \(startedId), state: \(String(describing: activity?.activityState))")
            print("[LiveActivity] attributesType: \(String(reflecting: SipTrackActivityAttributes.self))")
            let all = Activity<SipTrackActivityAttributes>.activities
            print("[LiveActivity] Total activities after request: \(all.count)")
            for a in all { print("[LiveActivity]   id=\(a.id) state=\(a.activityState)") }
            monitorState()
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    func update(bac: Double, drinkCount: Int, stageName: String, stageColorHex: String, elapsedMinutes: Int) {
        guard let activity else { return }
        let state = SipTrackActivityAttributes.ContentState(
            bac: bac,
            drinkCount: drinkCount,
            stageName: stageName,
            stageColorHex: stageColorHex,
            elapsedMinutes: elapsedMinutes,
            eventId: activity.content.state.eventId,
            quickDrinks: activity.content.state.quickDrinks
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
        Task { await activity.update(content) }
    }

    func end() {
        stateMonitorTask?.cancel()
        stateMonitorTask = nil
        guard let activity else { return }
        let content = ActivityContent(state: activity.content.state, staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .immediate) }
        self.activity = nil
    }

    private func monitorState() {
        guard let activity else { return }
        stateMonitorTask?.cancel()
        stateMonitorTask = Task {
            for await state in activity.activityStateUpdates {
                print("[LiveActivity] State update: \(state)")
                if state == .dismissed || state == .ended { break }
            }
        }
    }
}
