import UIKit
import OSLog
import FacebookCore
import TikTokBusinessSDK

/// Install attribution for Meta and TikTok ads: tells each network that an
/// install, open or Pro purchase came from one of its ads, so campaigns can be
/// measured and optimized.
///
/// Both SDKs log installs, launches and App Store purchases on their own, so
/// nothing is logged by hand here (that would double count). Both read the ATT
/// answer ConsentManager collects; with ATT denied they fall back to
/// SKAdNetwork, whose IDs are already in Info.plist.
enum AdAttribution {
    private static let log = Logger(subsystem: "com.siptrack.ads", category: "attribution")

    /// Call from `application(_:didFinishLaunchingWithOptions:)`.
    static func start(_ application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        // Reads FacebookAppID / FacebookClientToken from Info.plist.
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        startTikTok()
    }

    /// TikTok stays off without its App Secret, which reaches Info.plist only as
    /// the TIKTOK_APP_SECRET build setting (a GitHub secret in the TestFlight
    /// workflow, since the repo is public). Local and CI builds run without it.
    private static func startTikTok() {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let tiktokAppId = info["TikTokAppID"] as? String, !tiktokAppId.isEmpty,
              let accessToken = info["TikTokAccessToken"] as? String, !accessToken.isEmpty,
              let config = TikTokConfig(accessToken: accessToken, appId: appStoreId, tiktokAppId: tiktokAppId)
        else {
            log.info("TikTok SDK not configured; skipping")
            return
        }
        config.enablePaymentTracking()
        #if DEBUG
        config.enableDebugMode()
        #endif
        TikTokBusiness.initializeSdk(config) { success, error in
            if success {
                log.info("TikTok SDK started")
            } else {
                log.error("TikTok SDK failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            }
        }
    }

    /// Tracksip's App Store ID, which TikTok calls the app ID.
    private static let appStoreId = "6762666633"
}
