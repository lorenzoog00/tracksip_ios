import Foundation
import StoreKit
import Testing
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
