import UIKit
import UserMessagingPlatform
import AppTrackingTransparency

@MainActor
final class ConsentManager {
    static let shared = ConsentManager()
    private init() {}

    /// Call once on app launch. Handles UMP consent → ATT → AdMob init in the correct order.
    func gatherConsentAndInitializeAds() async {
        await requestUMPConsent()
        guard ConsentInformation.shared.canRequestAds else { return }
        await ATTrackingManager.requestTrackingAuthorization()
        AdManager.shared.initialize()
        await AdManager.shared.loadAppOpenAd()
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
