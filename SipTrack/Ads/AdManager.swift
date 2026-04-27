import SwiftUI
import Combine
import GoogleMobileAds

@MainActor
final class AdManager: ObservableObject {
    static let shared = AdManager()

    @Published var appOpenAdReady = false

    private var appOpenAd: AppOpenAd? = nil
    private var shownThisSession = false

    private init() {}

    // MARK: - SDK init (call from SipTrackApp)

    func initialize() {
        MobileAds.shared.start(completionHandler: nil)
    }

    // MARK: - App Open Ad

    func loadAppOpenAd() async {
        guard !appOpenAdReady else { return }
        do {
            appOpenAd = try await AppOpenAd.load(
                with: AdConfig.activeAppOpen,
                request: Request()
            )
            appOpenAdReady = true
        } catch {
            appOpenAdReady = false
        }
    }

    func showAppOpenAdIfReady(isPro: Bool) {
        guard !isPro, !shownThisSession, appOpenAdReady else { return }
        guard let root = UIApplication.shared
                .connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController else { return }
        appOpenAd?.present(from: root)
        shownThisSession = true
        appOpenAdReady = false
    }
}
