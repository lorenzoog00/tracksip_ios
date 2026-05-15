import SwiftUI
import GoogleMobileAds

/// Anchored adaptive banner — drops in at the bottom of any scroll view.
/// Shows only for free users. Collapses silently on load failure.
struct BannerAdView: View {
    @EnvironmentObject var appState: AppState
    @State private var adHeight: CGFloat = 50

    var body: some View {
        if !appState.isPro {
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

        func findRootVC() -> UIViewController? {
            UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
        }
    }
}
