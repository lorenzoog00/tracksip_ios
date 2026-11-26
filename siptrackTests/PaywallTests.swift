import CoreGraphics
import Foundation
import QuartzCore
import StoreKit
import SwiftUI
import Testing
import UIKit
@testable import siptrack

/// The paywall's pure pieces: price and trial wording, the savings badge, the
/// Pro feature list and which plan the button buys.
@MainActor
struct PaywallTests {
    @Test func savingsFloorsToWholePercent() {
        #expect(PaywallCopy.savingsPercent(monthly: Decimal(string: "1.99")!, yearly: Decimal(string: "19.99")!) == 16)
        #expect(PaywallCopy.savingsPercent(monthly: 2, yearly: 24) == nil)
        #expect(PaywallCopy.savingsPercent(monthly: 0, yearly: 10) == nil)
    }

    @Test func ctaNamesPriceAndPeriodWithoutTrial() {
        #expect(PaywallCopy.ctaLabel(period: .yearly, price: "$19.99", trial: nil) == "Continue · $19.99/yr")
        #expect(PaywallCopy.ctaLabel(period: .monthly, price: "$1.99", trial: nil) == "Continue · $1.99/mo")
    }

    @Test func ctaNamesTheTrial() {
        let trial = PaywallTrial(value: 3, unit: .day)
        #expect(PaywallCopy.ctaLabel(period: .yearly, price: "$19.99", trial: trial) == "Start your 3-day free trial")
    }

    @Test func renewalTermsStatePriceAndPeriod() {
        #expect(PaywallCopy.renewalTerms(period: .yearly, price: "$19.99", trial: nil)
                == "Auto-renews yearly at $19.99 until canceled. Cancel anytime in Settings.")
        #expect(PaywallCopy.renewalTerms(period: .monthly, price: "$1.99", trial: PaywallTrial(value: 1, unit: .week))
                == "1 week free, then $1.99 a month. Auto-renews until canceled. Cancel anytime in Settings.")
    }

    @Test func trialDurationsPluralize() {
        #expect(PaywallTrial(value: 3, unit: .day).duration == "3 days")
        #expect(PaywallTrial(value: 1, unit: .month).adjective == "1-month")
    }

    @Test func onlyRealProFeaturesAreListed() {
        let titles = PaywallFeatures.membership.map(\.title)
        #expect(titles.first == "Recovery plan every morning")
        #expect(!titles.contains { $0.localizedCaseInsensitiveContains("custom drink") || $0.localizedCaseInsensitiveContains("watch") })
    }

    @Test func copyAvoidsCompetitionWords() {
        let copy = [PaywallCopy.title, PaywallCopy.subtitle, PaywallCopy.allowance, PaywallCopy.alwaysFree, PaywallCopy.trust]
            + PaywallFeatures.membership.map(\.title)
        for banned in ["max", "peak", "streak", "rank", "record", "most drinks", "leaderboard"] {
            #expect(!copy.contains { $0.localizedCaseInsensitiveContains(banned) }, "\(banned)")
        }
    }

    @Test func selectionFallsBackToAPlanThatLoaded() {
        let monthly = PaywallPlanOption(period: .monthly, price: "$1.99", monthlyEquivalent: nil, savings: nil, trial: nil)
        #expect(PaywallPlansState.loaded([monthly]).resolvedSelection(.yearly) == .monthly)
        #expect(PaywallPlansState.loaded([monthly]).resolvedSelection(.monthly) == .monthly)
        #expect(PaywallPlansState.loading.resolvedSelection(.yearly) == nil)
    }
}

// MARK: - Screenshots

/// Draws the paywall on the smallest and the largest iPhone, at the default
/// and the largest accessibility text size, plus the loading, failed and
/// moving states and the whole screen at full length at both text sizes, and
/// saves each as a PNG in `build/paywall-shots/`, which CI uploads as the
/// `paywall-shots` artifact. With no Mac to hand these are the only look at
/// the screen before TestFlight, so every image is checked for its size and
/// for having really been drawn.
@MainActor
struct PaywallRenderTests {
    /// A phone's screen in points, with its portrait safe area.
    private struct Phone {
        let size: CGSize
        let safeArea: UIEdgeInsets

        /// iPhone SE: the smallest screen, status bar only.
        static let small = Phone(size: CGSize(width: 375, height: 667),
                                 safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0))
        /// iPhone 16 Pro Max: the largest, Dynamic Island and home indicator.
        static let large = Phone(size: CGSize(width: 440, height: 956),
                                 safeArea: UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0))

        /// The SE's width and safe area, tall enough to show the whole loaded
        /// screen at once, plan cards and inline purchase block included.
        static func fullLength(_ height: CGFloat) -> Phone {
            Phone(size: CGSize(width: small.size.width, height: height), safeArea: small.safeArea)
        }
    }

    /// The default text size and the largest accessibility one.
    private enum TextSize: String {
        case large, accessibility5

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .large: return .large
            case .accessibility5: return .accessibility5
            }
        }
    }

    private struct Shot {
        let phone: Phone
        let textSize: TextSize
        let plans: PaywallPlansState
        var animated = false
        /// Ends the file name for anything but loaded plans standing still.
        var variant: String? = nil
        /// Replaces the generated name, without the extension.
        var name: String? = nil

        /// `paywall-375x667-large.png`, `paywall-375x667-large-loading.png`, …
        var fileName: String {
            if let name { return name + ".png" }
            let parts = ["paywall", "\(Int(phone.size.width))x\(Int(phone.size.height))", textSize.rawValue, variant]
            return parts.compactMap { $0 }.joined(separator: "-") + ".png"
        }
    }

    /// The window a shot is drawn in. It reports the phone's safe area, not
    /// the simulator's: CI runs on whichever iPhone the runner has, which
    /// would give the SE a Dynamic Island and, where the window is bigger
    /// than that screen, could count the overhang as unsafe.
    private final class PhoneWindow: UIWindow {
        var phoneSafeArea = UIEdgeInsets.zero
        override var safeAreaInsets: UIEdgeInsets { phoneSafeArea }
    }

    private static let loadedPlans = PaywallPlansState.loaded([
        PaywallPlanOption(period: .yearly, price: "$19.99", monthlyEquivalent: "≈ $1.67/mo", savings: 16, trial: nil),
        PaywallPlanOption(period: .monthly, price: "$1.99", monthlyEquivalent: nil, savings: nil, trial: nil),
    ])

    private static let shots = [
        Shot(phone: .small, textSize: .large, plans: loadedPlans),
        Shot(phone: .small, textSize: .accessibility5, plans: loadedPlans),
        Shot(phone: .large, textSize: .large, plans: loadedPlans),
        Shot(phone: .large, textSize: .accessibility5, plans: loadedPlans),
        Shot(phone: .small, textSize: .large, plans: .loading, variant: "loading"),
        Shot(phone: .small, textSize: .large,
             plans: .failed("Plans are unavailable right now. Please try again later."), variant: "failed"),
        // Moving: the chips drift in one strip instead of sitting in a grid,
        // and the sample plan has not ticked anything yet.
        Shot(phone: .small, textSize: .large, plans: loadedPlans, animated: true, variant: "animated"),
        // The whole screen, top to bottom: at the largest text size the plan
        // cards and the purchase block are far below the first screenful.
        Shot(phone: .fullLength(1800), textSize: .large, plans: loadedPlans, name: "paywall-375-full-large"),
        Shot(phone: .fullLength(3600), textSize: .accessibility5, plans: loadedPlans, name: "paywall-375-full-ax5"),
    ]

    @Test func rendersAtSmallAndLargeSizes() async throws {
        let connected = await Self.windowScene()
        let scene = try #require(connected, "No connected window scene: the tests must run hosted in the app")
        let directory = Self.outputDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for shot in Self.shots {
            let image = try await Self.render(shot, in: scene)
            let png = try #require(image.pngData(), "\(shot.fileName): no PNG data")
            // Saved before the checks, so a bad render still reaches the artifact.
            try png.write(to: directory.appendingPathComponent(shot.fileName), options: .atomic)

            let size = shot.phone.size
            let pixels = try #require(image.cgImage, "\(shot.fileName): no bitmap")
            #expect(!png.isEmpty, "\(shot.fileName): empty PNG")
            #expect(image.size == size, "\(shot.fileName): \(image.size)")
            #expect(pixels.width == Int((size.width * image.scale).rounded()),
                    "\(shot.fileName): \(pixels.width) px wide at @\(image.scale)x")
            #expect(pixels.height == Int((size.height * image.scale).rounded()),
                    "\(shot.fileName): \(pixels.height) px tall at @\(image.scale)x")
            #expect(Self.isDrawn(pixels), "\(shot.fileName) came out blank, one flat color or partly empty")
        }
    }

    // MARK: - Drawing

    /// The free user's paywall as `ProView` shows it from an upsell: in a
    /// navigation stack with the inline title, the close button and Restore.
    private static func screen(for shot: Shot) -> some View {
        NavigationStack {
            PaywallScreen(
                plans: shot.plans,
                selected: .constant(.yearly),
                isPurchasing: false,
                errorMessage: nil,
                animated: shot.animated,
                onPurchase: {},
                onRetry: {}
            )
            .navigationTitle("Tracksip Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {} label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {} label: {
                        Text("Restore")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .environment(\.dynamicTypeSize, shot.textSize.dynamicTypeSize)
        .preferredColorScheme(.dark)
    }

    /// Shows the shot in its own window on the app's scene, lets SwiftUI lay
    /// it out, then snapshots the window at the screen's scale.
    private static func render(_ shot: Shot, in scene: UIWindowScene) async throws -> UIImage {
        let bounds = CGRect(origin: .zero, size: shot.phone.size)
        let window = PhoneWindow(windowScene: scene)
        window.phoneSafeArea = shot.phone.safeArea
        window.frame = bounds
        window.overrideUserInterfaceStyle = .dark
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
        let host = UIHostingController(rootView: screen(for: shot))
        window.rootViewController = host
        // Shown, not made key, so nothing else in the app loses its key window.
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        window.layoutIfNeeded()
        // Run-loop turns for SwiftUI to lay out, load the photos and measure
        // the chip row. The moving shot is taken before the sample plan's
        // first tick at 0.4 s, so it shows the frame the animation starts on.
        let settle: Duration = shot.animated ? .milliseconds(250) : .milliseconds(600)
        try await Task.sleep(for: settle)
        window.layoutIfNeeded()

        if host.view.safeAreaInsets != shot.phone.safeArea {
            print("\(shot.fileName): laid out with safe area \(host.view.safeAreaInsets), wanted \(shot.phone.safeArea)")
        }

        let format = UIGraphicsImageRendererFormat()
        // At most 8192 px tall, a texture size every renderer handles; only
        // the 3600 pt full-length shot comes down from the screen's scale.
        format.scale = min(scene.screen.scale, max(1, (8192 / shot.phone.size.height).rounded(.down)))
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        var drewHierarchy = false
        let snapshot = renderer.image { _ in
            drewHierarchy = window.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        if drewHierarchy, let pixels = snapshot.cgImage, isDrawn(pixels) {
            return snapshot
        }

        // drawHierarchy goes through the render server and can come back
        // empty, or cut off where the window runs past the simulator's
        // screen. The layer tree draws without it, minus blurs and materials.
        print("\(shot.fileName): drawHierarchy came back blank or partial, drawing the layer tree instead")
        let layers = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        if let pixels = layers.cgImage, isDrawn(pixels) {
            return layers
        }
        return snapshot
    }

    /// Whether the render really drew the screen: every sample opaque (the
    /// paywall's backdrop covers the whole window, so anything see-through
    /// is somewhere the render left empty) and not all one color. Samples a
    /// 24 x 48 grid, one row about every 20 pt down the 956 pt screen.
    private static func isDrawn(_ image: CGImage) -> Bool {
        let columns = 24
        let rows = 48
        var samples = [UInt8](repeating: 0, count: columns * rows * 4)
        let sampled = samples.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: columns, height: rows,
                                          bitsPerComponent: 8, bytesPerRow: columns * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard sampled else { return false }

        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: samples.count, by: 4) {
            if samples[offset + 3] < 250 { return false }
            let red = UInt32(samples[offset])
            let green = UInt32(samples[offset + 1])
            let blue = UInt32(samples[offset + 2])
            colors.insert(red << 16 | green << 8 | blue)
        }
        // A real screen gives hundreds; a blank one gives one.
        return colors.count >= 8
    }

    // MARK: - Setup

    /// The app's window scene. The tests run inside the app, so one is
    /// connected; wait up to five seconds for it to be active in case the run
    /// starts before launch has finished. `connectedScenes` is a Set, so pick
    /// the active one rather than whichever comes first.
    private static func windowScene() async -> UIWindowScene? {
        for _ in 0..<50 {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
                return active
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// `<repo>/build/paywall-shots/`, from this file's path
    /// (`<repo>/siptrackTests/PaywallTests.swift`). The simulator shares the
    /// Mac's disk, so the CI step after the tests uploads what lands here. A
    /// device can't reach that path, so there the shots go to its temp folder.
    private static func outputDirectory() -> URL {
        #if targetEnvironment(simulator)
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("paywall-shots", isDirectory: true)
        #else
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("paywall-shots", isDirectory: true)
        #endif
    }
}
