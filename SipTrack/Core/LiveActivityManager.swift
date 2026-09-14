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
            quickDrinks: quickDrinks
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
        do {
            activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            let startedId = activity?.id ?? "nil"
            #if DEBUG
            print("[LiveActivity] Started: \(startedId), state: \(String(describing: activity?.activityState))")
            #endif
            #if DEBUG
            print("[LiveActivity] attributesType: \(String(reflecting: SipTrackActivityAttributes.self))")
            #endif
            let all = Activity<SipTrackActivityAttributes>.activities
            #if DEBUG
            print("[LiveActivity] Total activities after request: \(all.count)")
            #endif
            #if DEBUG
            for a in all { print("[LiveActivity]   id=\(a.id) state=\(a.activityState)") }
            #endif
            monitorState()
        } catch {
            #if DEBUG
            print("[LiveActivity] Failed to start: \(error)")
            #endif
        }
    }

    func update(bac: Double, drinkCount: Int, stageName: String, stageColorHex: String, elapsedMinutes: Int, safeToDriveAt: Date?) {
        guard let activity else { return }
        let state = SipTrackActivityAttributes.ContentState(
            bac: bac,
            drinkCount: drinkCount,
            stageName: stageName,
            stageColorHex: stageColorHex,
            elapsedMinutes: elapsedMinutes,
            eventId: activity.content.state.eventId,
            quickDrinks: activity.content.state.quickDrinks,
            safeToDriveAt: safeToDriveAt
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
                #if DEBUG
                print("[LiveActivity] State update: \(state)")
                #endif
                if state == .dismissed || state == .ended { break }
            }
        }
    }
}
