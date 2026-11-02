import SwiftUI
import GoogleMobileAds

/// Anchored adaptive banner — drops in at the bottom of any scroll view.
/// Shows only for free users. Collapses silently on load failure.
struct BannerAdView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var consent = ConsentManager.shared
    @State private var adHeight: CGFloat = 50

    var body: some View {
        if !appState.isPro && consent.canRequestAds {
            BannerAdContainer(adUnitID: AdConfig.activeBanner, height: $adHeight)
                .frame(height: adHeight)
                .frame(maxWidth: .infinity)
        }
    }
}

// UIViewRepresentable wrapper for BannerView
private struct BannerAdContainer: UIViewRepresentable {
    let adUnitID: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        let banner = BannerView()
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = context.coordinator.findRootVC()
        let width = UIScreen.main.bounds.width
        banner.adSize = largeAnchoredAdaptiveBanner(width: width)
        banner.load(Request())
        container.addSubview(banner)
        banner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    class Coordinator: NSObject, BannerViewDelegate {
        @Binding var height: CGFloat
        init(height: Binding<CGFloat>) { _height = height }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            height = bannerView.adSize.size.height
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            height = 0
        }

        /// The banner keeps this for as long as it is on screen and only uses
        /// it when the ad is tapped, so it wants the stable root — not
        /// whatever was on top the moment the banner was built, which may be a
        /// sheet that is long gone by then.
        @MainActor
        func findRootVC() -> UIViewController? {
            PresentationAnchor.root()
        }
    }
}
