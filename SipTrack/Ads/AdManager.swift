import SwiftUI
import Combine
// import GoogleMobileAds   ← uncomment after adding the SDK package

/// Central ad coordinator — initialize once on app launch, call showAppOpenAd() on foreground.
@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()

    @Published var appOpenAdReady = false

    private var appOpenAd: AnyObject? = nil   // GADAppOpenAd when SDK is active
    private var shownThisSession = false

    private init() {}

    // MARK: - SDK init (call from SipTrackApp)

    func initialize() {
        // GADMobileAds.sharedInstance().start(completionHandler: nil)
        // After the SDK starts, preload the app open ad:
        // Task { await loadAppOpenAd() }
    }

    // MARK: - App Open Ad

    func loadAppOpenAd() async {
        guard !appOpenAdReady else { return }
        // do {
        //     appOpenAd = try await GADAppOpenAd.load(
        //         withAdUnitID: AdConfig.activeAppOpen,
        //         request: GADRequest()
        //     )
        //     appOpenAdReady = true
        // } catch {
        //     appOpenAdReady = false
        // }
    }

    func showAppOpenAdIfReady(isPro: Bool) {
        guard !isPro, !shownThisSession, appOpenAdReady else { return }
        guard let root = UIApplication.shared
                .connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController else { return }
        // (appOpenAd as? GADAppOpenAd)?.present(fromRootViewController: root)
        shownThisSession = true
        appOpenAdReady = false
        _ = root
    }
}
