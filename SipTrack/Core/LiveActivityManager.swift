import ActivityKit
import Foundation
import SipTrackActivityKit

@available(iOS 16.2, *)
@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()
    private var activity: Activity<SipTrackActivityAttributes>?
    private init() {}

    // Server push. The lock screen cannot run code, so between app launches the
    // BAC only changes when a push arrives: the app hands the server this night's
    // projected curve plus the activity's push token, and the server sends the
    // value for "now" every few minutes (functions/live-activity.js).
    private var pushToken: String?
    private var observedTokenFor: String?
    private var lastTemplate: SipTrackActivityAttributes.ContentState?
    private var lastSamples: [[String: Any]] = []
    private var syncedToken: String?
    /// The non-BAC parts of the last state the server holds. The server pushes
    /// that state back every 5 minutes, so when these change (a water, which
    /// leaves the BAC curve alone) it must hear about it, or its next push
    /// puts the old hydration back on the lock screen.
    private var syncedContentKey: String?

    private static func contentKey(_ state: SipTrackActivityAttributes.ContentState) -> String {
        [
            "\(state.drinkCount)",
            "\(state.hydrationBalance ?? 0)",
            "\(state.currentDrinkStartedAt?.timeIntervalSince1970 ?? 0)",
            state.currentDrinkName ?? "",
        ].joined(separator: "|")
    }
    private var pendingUpdate: Task<Void, Never>?
    private var pendingSync: Task<Void, Never>?

    /// Title for an alert on the next update, set by a lock-screen button.
    private var pendingAlert: String?

    /// Shown on the card while set; cleared by `clearAction()`.
    private var actionText: String?

    func alertOnNextUpdate(_ title: String) {
        pendingAlert = title
        actionText = title
    }

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
            do {
                activity = try Activity.request(attributes: attrs, content: content, pushType: .token)
                if let activity { observePushToken(activity) }
            } catch {
                // No push entitlement in this build: still show the lock screen,
                // it just updates only when the app runs.
                activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
            }
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
        if let activity { observePushToken(activity) }
        return activity
    }

    /// `pushSamples` is the projected curve from now on, passed only when it has
    /// changed (a drink, food or a profile edit); nil keeps the one already sent.
    func update(bac: Double, drinkCount: Int, stageName: String, stageColorHex: String, elapsedMinutes: Int, safeToDriveAt: Date?, soberAt: Date?, startedAt: Date?, hydrationBalance: Int? = nil, currentDrink: (name: String, symbol: String, startedAt: Date, minutes: Int)? = nil, pushSamples: [[String: Any]]? = nil) {
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
            updatedAt: Date(),
            hydrationBalance: hydrationBalance,
            currentDrinkName: currentDrink?.name,
            currentDrinkSymbol: currentDrink?.symbol,
            currentDrinkStartedAt: currentDrink?.startedAt,
            currentDrinkMinutes: currentDrink?.minutes,
            actionText: actionText
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
        if let alert = pendingAlert {
            // An alert update lights the screen and plays the notification
            // feedback (a vibration in silent mode): the confirmation that a tap
            // on the lock screen logged something, since a background launch
            // cannot drive the haptic engine.
            pendingAlert = nil
            let config = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: alert),
                body: LocalizedStringResource(stringLiteral: String(format: "BAC %.3f%%", bac)),
                sound: .default
            )
            pendingUpdate = Task { await activity.update(content, alertConfiguration: config) }
        } else {
            pendingUpdate = Task { await activity.update(content) }
        }
        lastTemplate = state
        if let pushSamples {
            lastSamples = pushSamples
            syncPush()
        } else if pushToken != nil,
                  pushToken != syncedToken || Self.contentKey(state) != syncedContentKey {
            syncPush()
        }
    }

    /// Waits for the last lock-screen update and server sync to finish. A
    /// lock-screen button runs in a background launch that iOS ends as soon as
    /// the intent returns, so the intent waits on this first.
    /// Takes the "added" message off the card, keeping everything else.
    func clearAction() async {
        actionText = nil
        guard let activity = currentActivity() else { return }
        var state = activity.content.state
        guard state.actionText != nil else { return }
        state.actionText = nil
        await pendingUpdate?.value
        await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(600)))
    }

    func flush() async {
        await pendingUpdate?.value
        await pendingSync?.value
    }

    private func observePushToken(_ activity: Activity<SipTrackActivityAttributes>) {
        guard observedTokenFor != activity.id else { return }
        observedTokenFor = activity.id
        if let data = activity.pushToken { pushToken = Self.hex(data) }
        Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                guard let self else { return }
                let token = Self.hex(data)
                guard token != self.pushToken || self.syncedToken != token else { continue }
                self.pushToken = token
                self.syncPush()
            }
        }
    }

    private func syncPush() {
        guard let token = pushToken, var template = lastTemplate else { return }
        template.actionText = nil
        guard let templateJSON = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(template))
        else { return }
        let samples = lastSamples
        // Recorded now, not on success, so the 10 s tick doesn't fire a second
        // sync while this one is in flight; a failure clears it to retry.
        let key = Self.contentKey(template)
        syncedContentKey = key
        let previous = pendingSync
        pendingSync = Task { [weak self] in
            await previous?.value
            let ok = await FirebaseManager.shared.syncLiveActivity(
                token: token, template: templateJSON, samples: samples
            )
            if ok {
                self?.syncedToken = token
            } else if self?.syncedContentKey == key {
                self?.syncedContentKey = nil
            }
        }
    }

    private func stopPush() {
        let wasSynced = syncedToken != nil || !lastSamples.isEmpty
        lastSamples = []
        lastTemplate = nil
        syncedToken = nil
        syncedContentKey = nil
        guard wasSynced else { return }
        let previous = pendingSync
        pendingSync = Task {
            await previous?.value
            _ = await FirebaseManager.shared.syncLiveActivity(token: nil, template: nil, samples: [])
        }
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
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
        pushToken = nil
        observedTokenFor = nil
        stopPush()
    }

}
