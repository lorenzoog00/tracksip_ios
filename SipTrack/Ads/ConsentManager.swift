import UIKit
import UserMessagingPlatform
import AppTrackingTransparency
import Combine
import OSLog

@MainActor
final class ConsentManager: ObservableObject {
    static let shared = ConsentManager()
    private init() {}
    @Published private(set) var canRequestAds = false
    @Published private(set) var requiresPrivacyOptions = false
    @Published var privacyError: String? = nil

    private let log = Logger(subsystem: "com.siptrack.ads", category: "consent")
    private var sdkStarted = false
    private var attHandled = false
    private var gathering = false

    /// Call once on app launch. Gathers UMP consent, then starts AdMob and preloads.
    /// ATT comes last on purpose: it must never stand between consent and ads.
    func gatherConsentAndInitializeAds() async {
        // Launch and the first didBecomeActive both land here; only one may run.
        guard !gathering else { return }
        gathering = true
        defer { gathering = false }

        await requestUMPConsent()
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        startAdsIfAllowed()
        await requestATTIfNeeded()
    }

    /// Call on every foreground. Retries a launch that never reached the ad SDK
    /// (no network, consent form still loading) and picks up a pending ATT prompt,
    /// so a single bad launch can't leave the app ad-free for its whole session.
    func refreshOnForeground() async {
        await requestATTIfNeeded()
        guard !canRequestAds else { return }
        await gatherConsentAndInitializeAds()
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
                self.startAdsIfAllowed()
                continuation.resume()
            }
        }
    }

    // MARK: - Ad start

    /// Flips the gate every ad view reads, starts the SDK once, and warms the
    /// full-screen formats. Safe to call repeatedly.
    private func startAdsIfAllowed() {
        var allowed = ConsentInformation.shared.canRequestAds
        #if DEBUG
        // Debug builds request Google's test units, so a consent hiccup in
        // development must not hide the ad slots we're trying to look at.
        if !allowed {
            log.warning("consent says no ads; forcing on for DEBUG test units")
            allowed = true
        }
        #endif

        guard allowed else {
            log.error("ads stay off: canRequestAds=false, status=\(String(describing: ConsentInformation.shared.consentStatus), privacy: .public)")
            canRequestAds = false
            return
        }

        if !sdkStarted {
            AdManager.shared.initialize()
            sdkStarted = true
            log.info("AdMob SDK started")
        }
        canRequestAds = true

        Task {
            async let appOpen: () = AdManager.shared.loadAppOpenAd()
            async let interstitial: () = AdManager.shared.loadInterstitialAd()
            _ = await (appOpen, interstitial)
        }
    }

    // MARK: - ATT

    /// The system drops the prompt silently when the app isn't active yet, which
    /// used to hang the whole launch path. Ask only when active, retry otherwise.
    private func requestATTIfNeeded() async {
        guard !attHandled else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            attHandled = true
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            log.info("ATT deferred: app not active yet")
            return
        }
        attHandled = true
        // Let any UMP modal finish dismissing before stacking a system alert on it.
        try? await Task.sleep(for: .seconds(1))
        let status = await ATTrackingManager.requestTrackingAuthorization()
        log.info("ATT status=\(status.rawValue, privacy: .public)")
    }

    private func requestUMPConsent() async {
        await withCheckedContinuation { continuation in
            let parameters = RequestParameters()
            parameters.isTaggedForUnderAgeOfConsent = false

            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    // Keep going: outside the EEA this still leaves canRequestAds true.
                    self.log.error("consent info update failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume()
                    return
                }

                guard
                    let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                    let root = scene.windows.first?.rootViewController
                else { continuation.resume(); return }

                ConsentForm.loadAndPresentIfRequired(from: root) { formError in
                    if let formError {
                        self.log.error("consent form failed: \(formError.localizedDescription, privacy: .public)")
                    }
                    continuation.resume()
                }
            }
        }
    }
}
