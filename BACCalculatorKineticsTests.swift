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

    // MARK: - Mitchell 2014 peak fixtures (kA(ABV) calibration gate)

    private func studyDrink(abv: Double, volumeForFortyGrams: Double) -> DrinkType {
        // 0.5 g/kg over 20 min, empty stomach (Mitchell 2014 protocol).
        DrinkType(id: "study-\(Int(abv))", name: "study", defaultVolumeMl: volumeForFortyGrams,
                  defaultAbv: abv, caloriesPerServing: 0, isPreset: false, icon: "flask",
                  defaultDrinkingDurationMinutes: 20)
    }

    private func peakAndTmax(abv: Double) -> (cmax: Double, tmaxMin: Double) {
        let profile = maleProfile(weight: 80)
        // vol so 40 g ethanol: g = vol·(abv/100)·0.789  ⇒  vol = 40 / (abv/100 · 0.789)
        let vol = 40.0 / ((abv / 100) * 0.789)
        let type = studyDrink(abv: abv, volumeForFortyGrams: vol)
        let start = Date()
        let entry = DrinkEntry(id: "s", eventId: "e", drinkTypeId: type.id, timestamp: start,
                               quantity: 1, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
        let curve = BACCalculator.bacTimeline(
            entries: [entry], drinkTypes: [type], profile: profile, eventStart: start
        )
        let peak = curve.max(by: { $0.bac < $1.bac })!
        return (peak.bac, peak.date.timeIntervalSince(start) / 60)
    }

    @Test func mitchell_cmaxOrdering_spiritsGtWineGtBeer() {
        let spirits = peakAndTmax(abv: 20).cmax
        let wine    = peakAndTmax(abv: 12.5).cmax
        let beer    = peakAndTmax(abv: 5).cmax
        #expect(spirits > wine)
        #expect(wine > beer)
    }

    @Test func mitchell_cmaxRatios_matchBioavailability() {
        // Absolute Cmax depends on the subject's r (Mitchell's cohort r≈0.58 vs our generic
        // r=0.68), but the *ratio* between beverages depends only on kA (how much peak is
        // lost to elimination during slower absorption). Mitchell ratios: wine/spirits≈0.80,
        // beer/spirits≈0.65. Assert with generous tolerance (kA anchors are approximate).
        let spirits = peakAndTmax(abv: 20).cmax
        let wine     = peakAndTmax(abv: 12.5).cmax
        let beer     = peakAndTmax(abv: 5).cmax
        #expect(spirits > 0)
        #expect((wine / spirits) > 0.65 && (wine / spirits) < 0.95)
        #expect((beer / spirits) > 0.50 && (beer / spirits) < 0.85)
    }

    @Test func mitchell_tmaxOrdering_andPlausibleRange() {
        let spirits = peakAndTmax(abv: 20).tmaxMin
        let wine     = peakAndTmax(abv: 12.5).tmaxMin
        let beer     = peakAndTmax(abv: 5).tmaxMin
        // Mitchell means: spirits 36, wine 54, beer 60 min. Strict ordering is guaranteed by
        // kA monotonicity; assert broad plausible bands rather than tight magnitudes.
        #expect(spirits < wine)
        #expect(wine < beer)
        #expect(spirits >= 15 && spirits <= 55)
        #expect(wine    >= 30 && wine    <= 80)
        #expect(beer    >= 35 && beer    <= 95)
    }

    // MARK: - Gulp instant-absorption invariant (preserved UX)

    @Test func gulp_secondDrinkInsideWindow_spikesImmediately() {
        // Two beers 1 min apart: the first beer's 20-min drinking window is interrupted by
        // the second, so it is "gulped" → its full ~14 g (≈0.0247 BAC) must register almost
        // immediately. Without the gulp branch, first-order absorption would show <0.001 at
        // 2 min, so the >0.02 threshold sharply verifies the instant-absorption invariant.
        let profile = maleProfile(weight: 80)
        let beerType = DrinkType.presets.first { $0.id == "beer" }!  // 355 mL @ 5%, 20-min window
        let start = Date()
        let gulpedPair = [
            beer("a", at: start),
            beer("b", at: start.addingTimeInterval(60))
        ]
        let at2min = start.addingTimeInterval(120)
        let curve = BACCalculator.bacTimeline(
            entries: gulpedPair, drinkTypes: [beerType], profile: profile, eventStart: start
        )
        let bacAt2 = curve.min(by: {
            abs($0.date.timeIntervalSince(at2min)) < abs($1.date.timeIntervalSince(at2min))
        })?.bac ?? 0
        #expect(bacAt2 > 0.02)
    }

    // MARK: - M-M-consistent time-to-sober

    @Test func hoursToZeroBAC_isLongerThanLinear() {
        // The M-M tail means clearing the last stretch takes longer than ΔC/β.
        let beta = 0.015
        let mm = BACCalculator.hoursToReduceBAC(from: 0.08, to: BACCalculator.michaelisKm, beta: beta)
        let linear = (0.08 - BACCalculator.michaelisKm) / beta
        #expect(mm > linear)
    }

    @Test func hoursToZeroBAC_belowFloor_returnsZero() {
        #expect(BACCalculator.hoursToZeroBAC(0) == 0)
        #expect(BACCalculator.hoursToZeroBAC(0.0003) == 0)
    }
}
