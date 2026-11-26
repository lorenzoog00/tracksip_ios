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
