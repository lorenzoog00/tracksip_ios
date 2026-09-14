import UIKit
import UserMessagingPlatform
import AppTrackingTransparency
import Combine

@MainActor
final class ConsentManager: ObservableObject {
    static let shared = ConsentManager()
    private init() {}
    @Published private(set) var canRequestAds = false
    @Published private(set) var requiresPrivacyOptions = false
    @Published var privacyError: String? = nil

    /// Call once on app launch. Handles UMP consent → ATT → AdMob init in the correct order.
    func gatherConsentAndInitializeAds() async {
        await requestUMPConsent()
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else { return }
        // Wait for any UMP modal to fully dismiss before presenting ATT.
        try? await Task.sleep(for: .seconds(1))
        await ATTrackingManager.requestTrackingAuthorization()
        AdManager.shared.initialize()
        canRequestAds = true
        async let appOpen: () = AdManager.shared.loadAppOpenAd()
        async let interstitial: () = AdManager.shared.loadInterstitialAd()
        _ = await (appOpen, interstitial)
    }

    func presentPrivacyOptions() async {
        privacyError = nil
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            privacyError = "Privacy choices could not be opened. Please try again."
            return
        }
        while let presented = root.presentedViewController { root = presented }
        canRequestAds = false
        AdManager.shared.clearAds()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ConsentForm.presentPrivacyOptionsForm(from: root) { error in
                if error != nil { self.privacyError = "Privacy choices could not be updated. Please try again." }
                self.requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                self.canRequestAds = ConsentInformation.shared.canRequestAds
                continuation.resume()
            }
        }
    }

    private func requestUMPConsent() async {
        await withCheckedContinuation { continuation in
            let parameters = RequestParameters()
            parameters.isTaggedForUnderAgeOfConsent = false

            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                guard error == nil else { continuation.resume(); return }

                guard
                    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let root = scene.windows.first?.rootViewController
                else { continuation.resume(); return }

                ConsentForm.loadAndPresentIfRequired(from: root) { _ in
                    continuation.resume()
                }
            }
        }
    }
}
