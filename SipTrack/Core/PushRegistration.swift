import UIKit
import UserNotifications

/// Remote push for friend requests. The permission prompt only appears once there is a
/// reason for it (the user sent a request or received one), never at launch.
enum PushRegistration {
    /// Called when a friend-request push is tapped. Set by `SipTrackApp`.
    static var onOpenFriends: (() -> Void)?

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

    /// Launch and sign-in: never prompts, only refreshes the token when already allowed.
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
        // The notification delegate must be in place before launch finishes or a
        // cold-start tap on a push is never delivered.
        _ = WaterReminderManager.shared
        Task { await PushRegistration.registerIfAuthorized() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = PushRegistration.hexString(deviceToken)
        Task { await FirebaseManager.shared.registerPushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("Remote notification registration failed: %@", error.localizedDescription)
    }
}
