import SwiftUI
import Combine
import GoogleMobileAds

/// Native ad card injected into the past-events list at position 3 (free users only).
struct NativeAdCardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var loader = NativeAdLoader()

    var body: some View {
        if !appState.isPro {
            Group {
                if loader.isLoaded {
                    NativeAdContent(loader: loader)
                } else {
                    Color.clear.frame(height: 0)
                }
            }
            .onAppear { loader.load(adUnitID: AdConfig.activeNative) }
            .onDisappear { loader.destroy() }
        }
    }
}

// MARK: - Ad content card

private struct NativeAdContent: View {
    @ObservedObject var loader: NativeAdLoader

    var body: some View {
        HStack(spacing: 12) {
            if let icon = loader.iconURL {
                AsyncImage(url: icon) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    AppColors.surface
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(loader.headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    Text("Ad")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.accentDim)
                        .cornerRadius(4)
                }
                if !loader.body.isEmpty {
                    Text(loader.body)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if !loader.callToAction.isEmpty {
                Text(loader.callToAction)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppColors.accent)
                    .cornerRadius(10)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }
}

// MARK: - Loader (wraps NativeAd lifecycle)

@MainActor
final class NativeAdLoader: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published var isLoaded = false
    @Published var headline = ""
    @Published var body = ""
    @Published var callToAction = ""
    @Published var iconURL: URL? = nil

    private var adLoader: AdLoader? = nil
    private var nativeAd: NativeAd? = nil

    func load(adUnitID: String) {
        guard !isLoaded else { return }
        let loader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        loader.load(Request())
        adLoader = loader
    }

    func destroy() {
        nativeAd = nil
        isLoaded = false
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in
            self.nativeAd = nativeAd
            self.headline = nativeAd.headline ?? ""
            self.body = nativeAd.body ?? ""
            self.callToAction = nativeAd.callToAction ?? ""
            self.iconURL = nativeAd.icon?.imageURL
            self.isLoaded = true
        }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in self.isLoaded = false }
    }
}
