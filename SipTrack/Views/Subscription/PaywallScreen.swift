import SwiftUI
import StoreKit

// MARK: - Copy

/// A free-trial introductory offer, reduced to what the paywall words.
struct PaywallTrial: Equatable {
    enum Unit { case day, week, month, year }

    let value: Int
    let unit: Unit

    private var noun: String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }

    /// "3-day", for "Start your 3-day free trial".
    var adjective: String { "\(value)-\(noun)" }

    /// "3 days", "1 week".
    var duration: String { "\(value) \(noun)\(value == 1 ? "" : "s")" }
}

extension PaywallTrial {
    /// nil unless the offer is a free trial.
    init?(offer: Product.SubscriptionOffer) {
        guard offer.paymentMode == .freeTrial else { return nil }
        let unit: Unit
        switch offer.period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: return nil
        }
        self.init(value: offer.period.value, unit: unit)
    }
}

struct PaywallFeature: Hashable {
    let icon: String
    let title: String
}

enum PaywallFeatures {
    static let pro: [PaywallFeature] = [
        PaywallFeature(icon: "sparkles", title: "AI Coach"),
        PaywallFeature(icon: "chart.bar.fill", title: "Stats"),
        PaywallFeature(icon: "calendar", title: "Calendar"),
        PaywallFeature(icon: "arrow.left.arrow.right", title: "Compare periods"),
        PaywallFeature(icon: "target", title: "Personal goals"),
        PaywallFeature(icon: "clock.arrow.circlepath", title: "Full history"),
        PaywallFeature(icon: "wand.and.stars", title: "AI drink lookup"),
        PaywallFeature(icon: "doc.text.fill", title: "PDF export"),
        PaywallFeature(icon: "eye.slash.fill", title: "No ads")
    ]

    static let membership: [PaywallFeature] =
        [PaywallFeature(icon: "sunrise.fill", title: "Recovery plan every morning")] + pro
}

enum PaywallCopy {
    static let title = "Wake up with a plan"
    static let subtitle = "After every night out, a recovery plan for how you actually feel."
    static let allowance = "Free: \(MorningCheckIn.freeMonthlyPlans) plans a month · Pro: every morning"
    static let alwaysFree = "Always free: live BAC, Live Activity, widgets and friends."
    static let trust = "BAC estimated with the Widmark formula."

    /// Whole percent saved by the yearly plan against twelve monthly
    /// payments, rounded down. nil when there is no saving to show.
    static func savingsPercent(monthly: Decimal, yearly: Decimal) -> Int? {
        guard monthly > 0 else { return nil }
        var ratio = (monthly * 12 - yearly) / (monthly * 12) * 100
        var floored = Decimal()
        NSDecimalRound(&floored, &ratio, 0, .down)
        let percent = NSDecimalNumber(decimal: floored).intValue
        return percent > 0 ? percent : nil
    }

    static func ctaLabel(period: SubscriptionPeriod, price: String, trial: PaywallTrial?) -> String {
        if let trial { return "Start your \(trial.adjective) free trial" }
        switch period {
        case .yearly: return "Continue · \(price)/yr"
        case .monthly: return "Continue · \(price)/mo"
        case .lifetime: return "Continue · \(price)"
        }
    }

    static func renewalTerms(period: SubscriptionPeriod, price: String, trial: PaywallTrial?) -> String {
        switch period {
        case .lifetime:
            return "One-time purchase. No subscription."
        case .yearly, .monthly:
            let yearly = period == .yearly
            if let trial {
                return "\(trial.duration) free, then \(price) \(yearly ? "a year" : "a month"). Auto-renews until canceled. Cancel anytime in Settings."
            }
            return "Auto-renews \(yearly ? "yearly" : "monthly") at \(price) until canceled. Cancel anytime in Settings."
        }
    }
}

// MARK: - Hero

/// The paywall's hero: `MorningPlan.sample` as a compact plan card, in the
/// plan screen's look, with real recovery-library photos. Its five ticks fill
/// in plan order when it appears; with `animated == false` (renders) or
/// Reduce Motion they all start ticked. Decorative: one accessibility element,
/// nothing to tap, no haptics.
struct PaywallPlanPreview: View {
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// How many items the animation has ticked so far, in plan order.
    @State private var tickedCount = 0

    static let accessibilitySummary =
        "Sample morning plan: water and electrolytes, ibuprofen, eggs on toast with a banana, a 20-minute walk and a nap."

    private static let breakfastPhoto = "PaywallBreakfast"
    /// One per activity, in plan order.
    private static let activityPhotos = ["PaywallWalk", "PaywallNap"]
    private static let firstTickDelay: Duration = .seconds(0.4)
    private static let tickInterval: Duration = .seconds(0.55)
    private static let breakfastPhotoHeight: CGFloat = 112
    private static let activityPhotoHeight: CGFloat = 76
    /// Rows and photo cards sit in a faint well inside the card.
    private static let well = Color.white.opacity(0.05)

    private var plan: MorningPlan { .sample }
    private var remedies: [PlanRemedy] { Array(plan.rightNow.prefix(2)) }
    private var activities: [PlanPhotoItem] { Array(plan.activities.prefix(Self.activityPhotos.count)) }
    /// Right now, then breakfast, then the activities: five for the sample.
    private var tickTotal: Int { remedies.count + 1 + activities.count }
    private var isStatic: Bool { !animated || reduceMotion }

    private func isTicked(_ index: Int) -> Bool {
        isStatic || index < tickedCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAMPLE MORNING PLAN")
                .font(.caption2.weight(.black))
                .tracking(2)
                .foregroundStyle(AppColors.accent)
                .fixedSize(horizontal: false, vertical: true)

            Text(plan.headline)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(AppColors.text)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            VStack(spacing: 6) {
                ForEach(Array(remedies.enumerated()), id: \.offset) { index, remedy in
                    remedyRow(remedy, isOn: isTicked(index))
                }
            }
            .padding(.top, 14)

            breakfastCard(isOn: isTicked(remedies.count))
                .padding(.top, 10)

            // fixedSize: side by side, both tiles take the taller one's height.
            activityLayout {
                ForEach(Array(activities.enumerated()), id: \.offset) { index, activity in
                    activityTile(activity, imageName: Self.activityPhotos[index],
                                 isOn: isTicked(remedies.count + 1 + index))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(radius: 22, borderTop: AppColors.accent.opacity(0.45))
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(AppColors.background)
                .shadow(color: AppColors.accent.opacity(0.14), radius: 24, y: 10)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilitySummary)
        .task(id: isStatic) { await tickInOrder() }
    }

    /// First tick 0.4 s after the card appears, then one every 0.55 s:
    /// 0.4, 0.95, 1.5, 2.05 and 2.6 s. Cancelled when the card leaves the
    /// screen; what is ticked stays ticked.
    private func tickInOrder() async {
        guard !isStatic, tickedCount < tickTotal else { return }
        do {
            try await Task.sleep(for: Self.firstTickDelay)
            while tickedCount < tickTotal {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                    tickedCount += 1
                }
                if tickedCount < tickTotal {
                    try await Task.sleep(for: Self.tickInterval)
                }
            }
        } catch {
            // Cancelled.
        }
    }

    /// Side by side; stacked at accessibility text sizes so the names keep
    /// the full width.
    private var activityLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    }

    private func remedyRow(_ remedy: PlanRemedy, isOn: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PaywallPlanTick(isOn: isOn)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                // Dropped at accessibility sizes to leave the title room.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: remedy.symbolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                }
                itemTitle(remedy.title, isOn: isOn)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Self.well, in: RoundedRectangle(cornerRadius: 12))
    }

    private func breakfastCard(isOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            photo(Self.breakfastPhoto, height: Self.breakfastPhotoHeight)
            HStack(alignment: .top, spacing: 10) {
                PaywallPlanTick(isOn: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    itemTitle(plan.breakfast.name, isOn: isOn)
                    if let when = plan.breakfast.when {
                        Text("\(Image(systemName: "clock")) \(when)")
                            .font(.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .background(Self.well)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func activityTile(_ item: PlanPhotoItem, imageName: String, isOn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            photo(imageName, height: Self.activityPhotoHeight)
            HStack(alignment: .top, spacing: 8) {
                PaywallPlanTick(isOn: isOn)
                itemTitle(item.name, isOn: isOn, font: .footnote.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.well)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// A bundled photo filling a fixed-height strip. The strip sets the size
    /// and the photo is an overlay, so its fill can never widen the layout.
    private func photo(_ name: String, height: CGFloat) -> some View {
        Self.well
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                Image(name)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
    }

    /// A ticked item reads as done, as on the plan screen: struck through and dimmed.
    private func itemTitle(_ title: String, isOn: Bool,
                           font: Font = .subheadline.weight(.semibold)) -> some View {
        Text(title)
            .font(font)
            .foregroundStyle(isOn ? AppColors.textSecondary : AppColors.text)
            .strikethrough(isOn, color: AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The plan screen's round gold tick, a size smaller. The fill pops in with
/// whatever animation changes `isOn`.
private struct PaywallPlanTick: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(isOn ? AppColors.accent : AppColors.border, lineWidth: 2)
            Circle()
                .fill(AppColors.accent)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.black)
                }
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Screen

/// One plan the paywall offers, already in display form: StoreKit's price
/// strings, the yearly saving and an eligible free trial.
struct PaywallPlanOption: Identifiable, Equatable {
    let period: SubscriptionPeriod
    let price: String
    /// "≈ $1.67/mo", shown under the yearly price.
    let monthlyEquivalent: String?
    let savings: Int?
    let trial: PaywallTrial?

    var id: SubscriptionPeriod { period }
}

enum PaywallPlansState: Equatable {
    case loading
    case failed(String)
    case loaded([PaywallPlanOption])
}

extension PaywallPlansState {
    /// The plan the button buys: `selected` when it loaded, else the first
    /// plan that did, else nil (loading, failed or nothing loaded).
    func resolvedSelection(_ selected: SubscriptionPeriod) -> SubscriptionPeriod? {
        guard case .loaded(let options) = self else { return nil }
        if options.contains(where: { $0.period == selected }) { return selected }
        return options.first?.period
    }
}

/// Side margin shared by the paywall's sections.
private enum PaywallLayout {
    static let gutter: CGFloat = 20
}

/// The free user's paywall, drawn from plain values and closures (no StoreKit,
/// no AppState) so tests can render it. Top to bottom: the sample plan, the
/// title, the free/Pro allowance, the other Pro features, what stays free and
/// the plans. The button, the renewal terms and the legal links sit pinned at
/// the bottom; at accessibility text sizes they follow the plans inline so
/// nothing has to squeeze. They only appear once plans have loaded, so a price
/// is always next to the button.
struct PaywallScreen: View {
    let plans: PaywallPlansState
    @Binding var selected: SubscriptionPeriod
    let isPurchasing: Bool
    let errorMessage: String?
    var animated: Bool = true
    let onPurchase: () -> Void
    let onRetry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let privacyURL = URL(string: "https://tracksip.online/policy")!

    private var inlinesPurchase: Bool { dynamicTypeSize.isAccessibilitySize }

    /// What the button buys. nil unless plans loaded and the list has one.
    private var selectedOption: PaywallPlanOption? {
        guard case .loaded(let options) = plans,
              let period = plans.resolvedSelection(selected) else { return nil }
        return options.first { $0.period == period }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PaywallPlanPreview(animated: animated)
                    .padding(.horizontal, PaywallLayout.gutter)
                    .padding(.top, 12)

                header
                    .padding(.horizontal, PaywallLayout.gutter)
                    .padding(.top, 28)

                PaywallFeatureStrip(features: PaywallFeatures.pro, animated: animated)
                    .padding(.top, 22)

                footnotes
                    .padding(.horizontal, PaywallLayout.gutter)
                    .padding(.top, 18)

                plansSection
                    .padding(.horizontal, PaywallLayout.gutter)
                    .padding(.top, 26)

                if inlinesPurchase, let option = selectedOption {
                    purchaseBlock(option)
                        .padding(.horizontal, PaywallLayout.gutter)
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 24)
        }
        .background { backdrop }
        .safeAreaInset(edge: .bottom, spacing: 0) { pinnedPurchaseBar }
    }

    private var backdrop: some View {
        ZStack(alignment: .top) {
            AppColors.background
            Ellipse()
                .fill(AppColors.accent.opacity(0.12))
                .frame(width: 360, height: 220)
                .blur(radius: 80)
                .offset(y: 40)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(PaywallCopy.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.textWarm, AppColors.text],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(PaywallCopy.subtitle)
                .font(.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(PaywallCopy.allowance)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(AppColors.accentDim, in: pillShape)
                .overlay { pillShape.stroke(AppColors.accent.opacity(0.35), lineWidth: 1) }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// A capsule; a rounded rectangle once accessibility sizes wrap the
    /// allowance onto several lines.
    private var pillShape: AnyShape {
        dynamicTypeSize.isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            : AnyShape(Capsule())
    }

    private var footnotes: some View {
        VStack(spacing: 8) {
            Text(PaywallCopy.alwaysFree)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Text(PaywallCopy.trust)
                .font(.footnote)
                .foregroundStyle(AppColors.textTertiary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var plansSection: some View {
        switch plans {
        case .loading:
            ProgressView("Loading plans…")
                .tint(AppColors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        case .failed(let message):
            failedView(message)
        case .loaded(let options):
            if options.isEmpty {
                failedView("Could not load plans")
            } else {
                let current = plans.resolvedSelection(selected)
                VStack(spacing: 10) {
                    ForEach(options) { option in
                        PaywallPlanCard(option: option, isSelected: option.period == current) {
                            withAnimation(.easeOut(duration: 0.18)) { selected = option.period }
                        }
                    }
                }
                .disabled(isPurchasing)
            }
        }
    }

    /// Today's error look: warning, message, Try Again.
    private func failedView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(AppColors.danger)
            Text(message)
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(AppColors.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 18)
                    .background(AppColors.accentDim, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var pinnedPurchaseBar: some View {
        if !inlinesPurchase, let option = selectedOption {
            purchaseBlock(option)
                .padding(.horizontal, PaywallLayout.gutter)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .background {
                    ZStack(alignment: .top) {
                        Rectangle().fill(.ultraThinMaterial)
                        AppColors.background.opacity(0.8)
                        AppColors.border.frame(height: 0.5)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    /// Error, button, renewal terms, legal links: price, period and terms
    /// always travel together.
    private func purchaseBlock(_ option: PaywallPlanOption) -> some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(AppColors.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            purchaseButton(option)

            Text(PaywallCopy.renewalTerms(period: option.period, price: option.price, trial: option.trial))
                .font(.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            legalLinks
        }
    }

    private func purchaseButton(_ option: PaywallPlanOption) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button(action: onPurchase) {
            Text(PaywallCopy.ctaLabel(period: option.period, price: option.price, trial: option.trial))
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Hidden, not removed, so the button keeps its size.
                .opacity(isPurchasing ? 0 : 1)
                .overlay {
                    if isPurchasing {
                        ProgressView().tint(.black)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(.black)
                .background(
                    LinearGradient(
                        colors: [AppColors.accentWarm, AppColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: shape
                )
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [Color.white.opacity(0.45), .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: AppColors.accent.opacity(0.45), radius: 18, y: 6)
        }
        .disabled(isPurchasing)
    }

    /// Side by side; stacked at accessibility sizes so neither link wraps
    /// into the other.
    private var legalLinks: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Link("Terms of Use", destination: Self.termsURL)
            if !stacked {
                Text("·").accessibilityHidden(true)
            }
            Link("Privacy Policy", destination: Self.privacyURL)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(AppColors.textSecondary)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Feature strip

/// The other Pro features as chips drifting left at 28 pt/s. The row is drawn
/// twice side by side and wraps after sliding one row plus the gap, when the
/// copy sits exactly where the original started, so the loop has no seam.
/// With Reduce Motion, `animated == false` (renders) or an accessibility text
/// size the chips sit still in a wrapping grid. One accessibility element.
struct PaywallFeatureStrip: View {
    let features: [PaywallFeature]
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// One row's width; 0 until it has been laid out.
    @State private var rowWidth: CGFloat = 0

    private static let pointsPerSecond: Double = 28
    private static let spacing: CGFloat = 8

    private var drifts: Bool {
        animated && !reduceMotion && !dynamicTypeSize.isAccessibilitySize
    }

    private var accessibilitySummary: String {
        "Also in Pro: " + features.map(\.title).joined(separator: ", ")
    }

    var body: some View {
        Group {
            if drifts {
                marquee
            } else {
                grid
                    .padding(.horizontal, PaywallLayout.gutter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// The rows overflow a zero-width frame that then takes the offered
    /// width, so the strip is exactly as wide as the screen and as tall as a
    /// chip; the overflow is clipped and faded at both edges.
    private var marquee: some View {
        TimelineView(.animation(paused: rowWidth == 0)) { context in
            HStack(spacing: Self.spacing) {
                chipRow
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                        rowWidth = width
                    }
                chipRow
            }
            .fixedSize()
            .offset(x: -drift(at: context.date))
        }
        .frame(width: 0, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .mask { edgeFade }
    }

    /// How far the rows have slid at `date`, wrapping every row plus gap.
    private func drift(at date: Date) -> CGFloat {
        guard rowWidth > 0 else { return 0 }
        let cycle = Double(rowWidth + Self.spacing)
        return CGFloat((date.timeIntervalSinceReferenceDate * Self.pointsPerSecond)
            .truncatingRemainder(dividingBy: cycle))
    }

    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var chipRow: some View {
        HStack(spacing: Self.spacing) {
            ForEach(features, id: \.self) { feature in
                chip(feature, inGrid: false)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Self.spacing) {
            ForEach(features, id: \.self) { feature in
                chip(feature, inGrid: true)
            }
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), alignment: .leading)]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: Self.spacing, alignment: .leading)]
    }

    /// Icon and title in a capsule. In the grid it fills its cell and becomes
    /// a rounded rectangle, since the title may wrap there.
    private func chip(_ feature: PaywallFeature, inGrid: Bool) -> some View {
        let shape = inGrid
            ? AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            : AnyShape(Capsule())
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: feature.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.accent)
            Text(feature.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: inGrid ? CGFloat.infinity : nil, alignment: .leading)
        .background(AppColors.surface, in: shape)
        .overlay { shape.stroke(AppColors.border, lineWidth: 1) }
    }
}

// MARK: - Plan card

/// A selectable plan: radio, name (BEST VALUE on yearly), what it saves or
/// how it bills, and the price with yearly's monthly equivalent. At
/// accessibility sizes the price moves under the name.
struct PaywallPlanCard: View {
    let option: PaywallPlanOption
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String {
        switch option.period {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }

    /// The trial when there is one; otherwise yearly's saving (or how it
    /// bills when the saving is unknown) and how monthly bills.
    private var subtitle: String {
        if let trial = option.trial { return "\(trial.adjective) free trial" }
        switch option.period {
        case .yearly:
            if let savings = option.savings { return "Save \(savings)% vs monthly" }
            return "Billed once a year"
        case .monthly:
            return "Billed monthly · cancel anytime"
        case .lifetime:
            return "One-time purchase"
        }
    }

    private var isBestValue: Bool { option.period == .yearly }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
                radio
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        details
                        price(alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    details
                    Spacer(minLength: 8)
                    price(alignment: .trailing)
                        .fixedSize()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(AppColors.surface)
                    .overlay {
                        if isSelected {
                            shape.fill(
                                LinearGradient(
                                    colors: [AppColors.accent.opacity(0.18), AppColors.accent.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
            }
            .overlay {
                shape.stroke(isSelected ? AppColors.accent : AppColors.border,
                             lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: AppColors.accent.opacity(isSelected ? 0.22 : 0), radius: 14, y: 4)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var radio: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? AppColors.accent : AppColors.border,
                        lineWidth: isSelected ? 2 : 1.5)
            if isSelected {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 11, height: 11)
            }
        }
        .frame(width: 22, height: 22)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The badge drops under the name when both don't fit on a line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    titleText
                    badge
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    badge
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AppColors.text)
    }

    @ViewBuilder
    private var badge: some View {
        if isBestValue {
            Text("BEST VALUE")
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func price(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(option.price)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.text)
            if let monthlyEquivalent = option.monthlyEquivalent {
                Text(monthlyEquivalent)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
