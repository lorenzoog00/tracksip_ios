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
