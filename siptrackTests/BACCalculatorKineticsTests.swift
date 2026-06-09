//
//  BACCalculatorKineticsTests.swift
//  siptrackTests
//
//  Validates the Michaelis–Menten elimination + concentration-dependent absorption
//  model against the published pharmacokinetics (Mitchell 2014; Toxics 2023; Jones).
//

import Testing
import Foundation
@testable import siptrack

struct BACCalculatorKineticsTests {

    // MARK: - Vmax calibration

    @Test func vmax_isAboveBeta_andReproducesBetaAtReference() {
        let beta = 0.0138
        let vmax = BACCalculator.vmax(beta: beta)
        // Vmax must exceed the observed slope...
        #expect(vmax > beta)
        // ...and the M-M rate at the 0.08 reference must equal beta.
        let km = BACCalculator.michaelisKm
        let rateAtRef = vmax * 0.08 / (km + 0.08)
        #expect(abs(rateAtRef - beta) < 1e-6)
    }

    // MARK: - absorptionRateEmpty(abv:)

    @Test func absorptionRate_peaksNearTwentyPercent() {
        let beer     = BACCalculator.absorptionRateEmpty(abv: 5)
        let wine     = BACCalculator.absorptionRateEmpty(abv: 12.5)
        let mixed20  = BACCalculator.absorptionRateEmpty(abv: 20)
        let neat40   = BACCalculator.absorptionRateEmpty(abv: 40)
        // Fastest near ~20% v/v; dilute and very strong are slower.
        #expect(mixed20 > wine)
        #expect(wine > beer)
        #expect(mixed20 > neat40)
        #expect(beer > 0)
    }

    @Test func absorptionRate_clampsAtExtremes() {
        #expect(BACCalculator.absorptionRateEmpty(abv: 0) > 0)
        #expect(BACCalculator.absorptionRateEmpty(abv: 100) > 0)
    }

    // MARK: - Shared helpers (used by later tasks)

    private func maleProfile(weight: Double = 80) -> UserProfile {
        var p = UserProfile(); p.weightKg = weight; p.sex = .male; p.birthYear = 1990
        return p
    }

    private func beer(_ id: String, at: Date, qty: Int = 1) -> DrinkEntry {
        DrinkEntry(id: id, eventId: "e", drinkTypeId: "beer", timestamp: at,
                   quantity: qty, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
    }

    // MARK: - Michaelis–Menten tail behaviour

    @Test func mmTail_extendsTimeToZeroVsLinear() {
        // Compare the integrated tail against a pure linear β extrapolation from the peak.
        let profile = maleProfile()
        let beerType = DrinkType.presets.first { $0.id == "beer" }!
        let start = Date()
        let entries = [beer("d1", at: start, qty: 3)]
        let curve = BACCalculator.bacTimeline(
            entries: entries, drinkTypes: [beerType], profile: profile, eventStart: start
        )
        let peak = curve.map(\.bac).max() ?? 0
        #expect(peak > 0)
        // Time from peak to (near) zero under M-M must exceed the linear estimate peak/β,
        // because elimination slows below ~0.02.
        let beta = BACCalculator.eliminationRate(profile: profile)
        let linearHoursToZero = peak / beta
        guard let peakPoint = curve.max(by: { $0.bac < $1.bac }),
              let zeroPoint  = curve.last(where: { $0.bac > 0 }) else { return }
        let mmHours = zeroPoint.date.timeIntervalSince(peakPoint.date) / 3600
        #expect(mmHours > linearHoursToZero)
    }

    @Test func highBAC_matchesZeroOrderWithinFivePercent() {
        // In the 0.05–0.10 regime M-M ≈ β (Vmax calibrated at 0.08). Spot-check the
        // descending slope over ~30+ min equals β within ±5%.
        let profile = maleProfile()
        let beerType = DrinkType.presets.first { $0.id == "beer" }!
        let start = Date()
        let entries = [beer("d1", at: start, qty: 6)]   // ~0.10 then decline
        let curve = BACCalculator.bacTimeline(
            entries: entries, drinkTypes: [beerType], profile: profile, eventStart: start
        )
        let peakBac = curve.map(\.bac).max() ?? 0
        let desc = curve.drop { $0.bac < peakBac }      // from peak onward
        let around = Array(desc.filter { $0.bac <= 0.09 && $0.bac >= 0.06 })
        guard let a = around.first,
              let b = around.first(where: { $0.date.timeIntervalSince(a.date) >= 1800 }) else { return }
        let slopePerHour = (a.bac - b.bac) / (b.date.timeIntervalSince(a.date) / 3600)
        let beta = BACCalculator.eliminationRate(profile: profile)
        #expect(abs(slopePerHour - beta) / beta < 0.05)
    }
}
