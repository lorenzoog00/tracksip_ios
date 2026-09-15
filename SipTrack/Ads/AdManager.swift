import SwiftUI
import Combine
import GoogleMobileAds

@MainActor
final class AdManager: NSObject, ObservableObject, FullScreenContentDelegate {
    static let shared = AdManager()

    @Published var appOpenAdReady = false
    @Published var interstitialReady = false

    private var appOpenAd: AppOpenAd? = nil
    private var interstitialAd: InterstitialAd? = nil
    private var shownThisSession = false
    private var summaryBrowseToggle = false

    private override init() {}

    // MARK: - SDK init

    func initialize() {
        MobileAds.shared.start(completionHandler: nil)
    }

    // MARK: - App Open Ad

    func loadAppOpenAd() async {
        guard ConsentManager.shared.canRequestAds else { return }
        guard !appOpenAdReady else { return }
        do {
            appOpenAd = try await AppOpenAd.load(
                with: AdConfig.activeAppOpen,
                request: Request()
            )
            guard ConsentManager.shared.canRequestAds else { clearAds(); return }
            appOpenAd?.fullScreenContentDelegate = self
            appOpenAdReady = true
        } catch {
            appOpenAdReady = false
        }
    }

    func showAppOpenAdIfReady(isPro: Bool) {
        guard ConsentManager.shared.canRequestAds else { return }
        guard !isPro, !shownThisSession, appOpenAdReady else { return }
        guard let root = rootViewController() else { return }
        appOpenAd?.present(from: root)
        shownThisSession = true
        appOpenAdReady = false
    }

    // MARK: - Interstitial Ad

    func loadInterstitialAd() async {
        guard ConsentManager.shared.canRequestAds else { return }
        guard !interstitialReady else { return }
        do {
            interstitialAd = try await InterstitialAd.load(
                with: AdConfig.activeInterstitial,
                request: Request()
            )
            guard ConsentManager.shared.canRequestAds else { clearAds(); return }
            interstitialAd?.fullScreenContentDelegate = self
            interstitialReady = true
        } catch {
            interstitialReady = false
        }
    }

    func showInterstitialIfReady(isPro: Bool) {
        guard ConsentManager.shared.canRequestAds else { return }
        guard !isPro, interstitialReady else { return }
        guard let root = rootViewController() else { return }
        interstitialAd?.present(from: root)
        interstitialReady = false
    }

    // Shows only on every other call — for summary browsing so it's not shown every tap.
    func showInterstitialForBrowse(isPro: Bool) {
        summaryBrowseToggle.toggle()
        guard summaryBrowseToggle else { return }
        showInterstitialIfReady(isPro: isPro)
    }

    // MARK: - FullScreenContentDelegate (reload after dismiss)

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in
            if ad is AppOpenAd {
                self.appOpenAd = nil
                await self.loadAppOpenAd()
            } else if ad is InterstitialAd {
                self.interstitialAd = nil
                await self.loadInterstitialAd()
            }
        }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in
            if ad is AppOpenAd {
                self.appOpenAdReady = false
                self.appOpenAd = nil
                await self.loadAppOpenAd()
            } else if ad is InterstitialAd {
                self.interstitialReady = false
                self.interstitialAd = nil
                await self.loadInterstitialAd()
            }
        }
    }

    // MARK: - Helper

    func clearAds() {
        appOpenAd = nil
        interstitialAd = nil
        appOpenAdReady = false
        interstitialReady = false
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
