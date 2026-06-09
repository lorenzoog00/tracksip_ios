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
}
