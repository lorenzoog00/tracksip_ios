import Foundation
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {

    static let shared = WatchBridge()

    weak var appState: AppState?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Push state to Watch

    func pushState() {
        guard WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }
        guard let appState else { return }

        let drinkTypes = appState.allDrinkTypes.prefix(16).map { dt -> [String: Any] in
            ["id": dt.id, "name": dt.name, "icon": dt.sfSymbol, "abv": dt.defaultAbv]
        }

        var ctx: [String: Any] = [
            "hasActiveEvent": false,
            "drinkTypes": drinkTypes
        ]

        if let event = appState.activeEvent {
            let bac  = appState.currentBAC(for: event.id)
            let beta = BACCalculator.eliminationRate(profile: appState.userProfile)
            ctx["hasActiveEvent"]  = true
            ctx["eventId"]         = event.id
            ctx["eventName"]       = event.displayName
            ctx["eventStart"]      = event.startTime.timeIntervalSince1970
            ctx["drinkCount"]      = appState.totalDrinks(for: event.id)
            ctx["currentBAC"]      = bac
            ctx["bacTimestamp"]    = Date().timeIntervalSince1970
            ctx["eliminationRate"] = beta
        }

        try? WCSession.default.updateApplicationContext(ctx)
    }

    // MARK: - Incoming messages from Watch

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let action = message["action"] as? String else {
            replyHandler(["ok": false]); return
        }
        Task { @MainActor in
            guard let appState else { replyHandler(["ok": false]); return }
            switch action {

            case "startEvent":
                // A night is already running (a double tap, or a second message before
                // the Watch saw the new state), or nobody is signed in: start nothing,
                // just send the Watch the current state.
                let started = WatchBridge.mayStartNight(
                    hasActiveNight: appState.activeEvent != nil,
                    signedInUid: FirebaseManager.shared.currentUserId()
                )
                if started {
                    appState.createEvent(name: nil, drivingMode: false, bacLimit: nil)
                }
                pushState()
                replyHandler(["ok": started, "hasActiveEvent": appState.activeEvent != nil])

            case "addDrink":
                guard let eventId = appState.activeEvent?.id,
                      let typeId  = message["drinkTypeId"] as? String else {
                    replyHandler(["ok": false]); return
                }
                appState.addDrink(eventId: eventId, drinkTypeId: typeId)
                pushState()
                replyHandler(["ok": true])

            case "addWater":
                guard let eventId = appState.activeEvent?.id else {
                    replyHandler(["ok": false]); return
                }
                appState.addWater(eventId: eventId)
                replyHandler(["ok": true])

            case "endEvent":
                let eventId = message["eventId"] as? String ?? appState.activeEvent?.id
                if let id = eventId { appState.endEvent(id) }
                pushState()
                replyHandler(["ok": true])

            case "requestState":
                pushState()
                replyHandler(["ok": true])

            default:
                replyHandler(["ok": false])
            }
        }
    }

    /// The Watch may start a night only with none running and someone signed in.
    nonisolated static func mayStartNight(hasActiveNight: Bool, signedInUid: String?) -> Bool {
        !hasActiveNight && signedInUid != nil
    }

    // MARK: - WCSessionDelegate boilerplate

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
