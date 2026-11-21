import UIKit
import UserNotifications
import FirebaseAuth

/// Where a tapped remote push leads. The server sends `route` (and `username`)
/// beside `aps`; pushes from before that field existed are friend requests.
nonisolated enum PushRoute: Equatable, Sendable {
    /// My friends: a request arrived or was accepted.
    case friends
    /// The add sheet for someone who has you in their contacts.
    case add(username: String)
    /// Social, where someone without a profile picks a username.
    case social
    /// The comment sheet of one night: a reaction, comment, reply or mention on it.
    case thread(owner: String, startedAt: Int64)

    init(userInfo: [AnyHashable: Any]) {
        switch userInfo["route"] as? String {
        case "add":
            if let name = (userInfo["username"] as? String)?.lowercased(), FriendLink.isValid(name) {
                self = .add(username: name)
            } else {
                self = .social
            }
        case "social":
            self = .social
        case "thread":
            // The owner is a path segment of the thread doc id, so no slash.
            if let owner = userInfo["owner"] as? String, !owner.isEmpty, !owner.contains("/"),
               let startedAt = Self.millis(userInfo["started_at"]) {
                self = .thread(owner: owner, startedAt: startedAt)
            } else {
                self = .social
            }
        default:
            self = .friends
        }
    }

    /// Epoch milliseconds as APNs hands them over: an NSNumber from the JSON, or a
    /// Swift Int, Int64 or Double. Nil for anything else, fractions, or not positive.
    private static func millis(_ value: Any?) -> Int64? {
        let ms: Int64?
        switch value {
        case let v as Int64: ms = v
        case let v as Int: ms = Int64(v)
        case let v as Double: ms = v.isFinite ? Int64(exactly: v) : nil
        case let v as NSNumber: ms = Int64(exactly: v.doubleValue)
        default: ms = nil
        }
        guard let ms, ms > 0 else { return nil }
        return ms
    }
}

/// Remote push for friend requests and contacts joining. The permission prompt only
/// appears once there is a reason for it (the user sent a request or received one),
/// never at launch.
enum PushRegistration {
    /// Called when a remote push is tapped. Set by `SipTrackApp`.
    static var onOpen: ((PushRoute) -> Void)?

    /// Ask only while undecided, and only once a request exists in either direction.
    nonisolated static func shouldAsk(sentCount: Int, incomingCount: Int, status: UNAuthorizationStatus) -> Bool {
        status == .notDetermined && (sentCount > 0 || incomingCount > 0)
    }

    nonisolated static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    /// APNs wants lowercase hex; the server validates `/^[0-9a-f]{32,400}$/`.
    nonisolated static func hexString(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Prompts (if `shouldAsk`) and registers on grant. Safe to call repeatedly.
    static func requestIfNeeded(sentCount: Int = 0, incomingCount: Int = 0) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if shouldAsk(sentCount: sentCount, incomingCount: incomingCount, status: status) {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } else if isAuthorized(status) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Sign-in: never prompts, only refreshes the token when already allowed.
    /// Launch needs no call: it registers unconditionally (see `AppDelegate`).
    static func registerIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if isAuthorized(status) { UIApplication.shared.registerForRemoteNotifications() }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // First, before anything reads Firebase: configuring it any earlier (in
        // App.init) left phone auth half set up and crashed 1.0.9 on launch. The
        // stores come right after, so push taps and lock-screen intents find them.
        NSLog("DIAG2 didFinishLaunching start")
        FirebaseSetup.configureIfNeeded()
        _ = AppServices.shared
        // The notification delegate must be in place before launch finishes or a
        // cold-start tap on a push is never delivered.
        _ = WaterReminderManager.shared
        // Firebase phone auth's silent check needs an APNs token. iOS hands one
        // over without asking the user and shows nothing; our server only gets
        // it once notifications are allowed (see below).
        application.registerForRemoteNotifications()
        AdAttribution.start(application, launchOptions: launchOptions)
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Never straight to Auth: if its phone-auth setup didn't run, this traps
        // (TestFlight 1.0.9's launch crash). FirebaseManager waits until it's ready.
        FirebaseManager.shared.setAPNSToken(deviceToken)
        let token = PushRegistration.hexString(deviceToken)
        // Launch now registers without permission, for phone auth. Uploading only
        // when allowed keeps things as they were: registering used to happen
        // only after permission. Checked in the task so this callback never blocks.
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            guard PushRegistration.isAuthorized(status) else { return }
            await FirebaseManager.shared.registerPushToken(token)
        }
    }

    /// Firebase phone auth's silent push is the only one handled here. Friend
    /// and thread pushes are visible ones, opened through `WaterReminderManager`.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        _ = FirebaseManager.shared.handlesAuthNotification(userInfo)
        completionHandler(.noData)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Remote notification registration failed: %@", error.localizedDescription)
    }
}
