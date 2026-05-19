import Foundation
import SwiftUI
import Combine
import WatchConnectivity
import WatchKit

struct WatchDrinkType: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let abv: Double
}

@MainActor
final class WatchState: NSObject, ObservableObject {

    static let shared = WatchState()

    @Published var hasActiveEvent  = false
    @Published var eventId         = ""
    @Published var eventName       = "Night Out"
    @Published var eventStart      = Date()
    @Published var drinkCount      = 0
    @Published var currentBAC      = 0.0
    @Published var drinkTypes: [WatchDrinkType] = []
    @Published var isPhoneReachable = false
    @Published var isSending        = false

    // Snapshot from the last phone push. The local timer derives currentBAC
    // from these instead of showing the frozen value.
    private var bacAtTimestamp: Double = 0
    private var bacTimestamp:   Date   = Date()
    private var eliminationRate: Double = 0.015   // β default until phone sends its own

    private var localBACTimer: AnyCancellable?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - BAC color

    var bacColor: Color {
        switch currentBAC {
        case ..<0.04:  return Color(red: 0.22, green: 0.85, blue: 0.50)
        case ..<0.08:  return Color(red: 1.0,  green: 0.84, blue: 0.0)
        case ..<0.15:  return Color(red: 1.0,  green: 0.50, blue: 0.0)
        default:       return Color(red: 0.90, green: 0.20, blue: 0.20)
        }
    }

    var stageName: String {
        switch currentBAC {
        case ..<0.02:  return "Sober"
        case ..<0.04:  return "Buzzed"
        case ..<0.08:  return "Tipsy"
        case ..<0.15:  return "Impaired"
        default:       return "Drunk"
        }
    }

    // MARK: - Actions

    func requestState() {
        send(["action": "requestState"])
    }

    func startEvent() {
        isSending = true
        sendWithReply(["action": "startEvent"]) { [weak self] in
            self?.isSending = false
        }
    }

    func addDrink(drinkTypeId: String) {
        WKInterfaceDevice.current().play(.click)
        drinkCount += 1
        send(["action": "addDrink", "drinkTypeId": drinkTypeId])
    }

    func addWater() {
        WKInterfaceDevice.current().play(.click)
        send(["action": "addWater"])
    }

    func endEvent() {
        isSending = true
        sendWithReply(["action": "endEvent", "eventId": eventId]) { [weak self] in
            self?.isSending = false
        }
    }

    // MARK: - Local BAC timer

    private func startLocalBACTimer() {
        guard localBACTimer == nil else { return }
        localBACTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.currentBAC = self.computeLocalBAC()
            }
    }

    private func stopLocalBACTimer() {
        localBACTimer?.cancel()
        localBACTimer = nil
    }

    private func computeLocalBAC() -> Double {
        guard hasActiveEvent else { return 0 }
        let hours = Date().timeIntervalSince(bacTimestamp) / 3600
        return max(0, bacAtTimestamp - eliminationRate * hours)
    }

    // MARK: - Helpers

    private func send(_ message: [String: Any]) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    private func sendWithReply(_ message: [String: Any], completion: @escaping () -> Void) {
        guard WCSession.default.isReachable else { completion(); return }
        WCSession.default.sendMessage(message, replyHandler: { _ in
            Task { @MainActor in completion() }
        }, errorHandler: { _ in
            Task { @MainActor in completion() }
        })
    }

    private func apply(_ ctx: [String: Any]) {
        let hadEvent   = hasActiveEvent
        hasActiveEvent = ctx["hasActiveEvent"] as? Bool   ?? false
        eventId        = ctx["eventId"]        as? String ?? ""
        eventName      = ctx["eventName"]      as? String ?? "Night Out"
        drinkCount     = ctx["drinkCount"]     as? Int    ?? 0

        if let ts = ctx["eventStart"] as? Double {
            eventStart = Date(timeIntervalSince1970: ts)
        }

        // Parse BAC snapshot. If the phone sends the new fields, store them
        // and run local extrapolation. Fall back to the raw value for older builds.
        if let bac  = ctx["currentBAC"]      as? Double,
           let ts   = ctx["bacTimestamp"]    as? Double,
           let beta = ctx["eliminationRate"] as? Double {
            bacAtTimestamp  = bac
            bacTimestamp    = Date(timeIntervalSince1970: ts)
            eliminationRate = beta
            currentBAC      = computeLocalBAC()
        } else if let bac = ctx["currentBAC"] as? Double {
            currentBAC = bac
        }

        if let types = ctx["drinkTypes"] as? [[String: Any]] {
            drinkTypes = types.compactMap { d in
                guard let id   = d["id"]   as? String,
                      let name = d["name"] as? String,
                      let icon = d["icon"] as? String,
                      let abv  = d["abv"]  as? Double else { return nil }
                return WatchDrinkType(id: id, name: name, icon: icon, abv: abv)
            }
        }

        // Manage the local timer lifecycle.
        if hasActiveEvent {
            if !hadEvent { startLocalBACTimer() }
        } else {
            stopLocalBACTimer()
            currentBAC = 0
        }
    }
}

extension WatchState: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            isPhoneReachable = WCSession.default.isReachable
            requestState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            if session.isReachable { requestState() }
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in apply(ctx) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any]) {
        Task { @MainActor in apply(message) }
    }
}
