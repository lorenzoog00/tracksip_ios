import Foundation

enum AdConfig {
    static let appId         = "ca-app-pub-9583249699000184~7133030963"
    static let banner        = "ca-app-pub-9583249699000184/1301060299"
    static let appOpen       = "ca-app-pub-9583249699000184/6783736085"
    static let native        = "ca-app-pub-9583249699000184/5470654414"
    // TODO: replace with real interstitial unit ID from AdMob console
    static let interstitial  = "ca-app-pub-9583249699000184/XXXXXXXXXX"

    // Swap to test IDs in debug builds
    static var activeBanner:       String { isDebug ? "ca-app-pub-3940256099942544/2934735716" : banner }
    static var activeAppOpen:      String { isDebug ? "ca-app-pub-3940256099942544/5575463023" : appOpen }
    static var activeNative:       String { isDebug ? "ca-app-pub-3940256099942544/3986624511" : native }
    static var activeInterstitial: String { isDebug ? "ca-app-pub-3940256099942544/4411468910" : interstitial }

    private static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
