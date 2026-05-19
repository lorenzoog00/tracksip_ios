//
//  BACCalculatorCoreTests.swift
//  siptrackTests
//

import Testing
@testable import siptrack

struct BACCalculatorCoreTests {

    // MARK: - calculateAlcohol

    @Test func calculateAlcohol_standardBeer() {
        // 355 mL × 5% ABV × 1 serving × 0.789 g/mL = 14.0 g
        let grams = BACCalculator.calculateAlcohol(volumeMl: 355, abv: 5.0, quantity: 1)
        #expect(abs(grams - 14.0) < 0.1)
    }

    @Test func calculateAlcohol_shot() {
        // 44 mL × 40% × 1 × 0.789 = 13.89 g
        let grams = BACCalculator.calculateAlcohol(volumeMl: 44, abv: 40.0, quantity: 1)
        #expect(abs(grams - 13.89) < 0.1)
    }

    @Test func calculateAlcohol_scalesWithQuantity() {
        let single = BACCalculator.calculateAlcohol(volumeMl: 355, abv: 5.0, quantity: 1)
        let triple = BACCalculator.calculateAlcohol(volumeMl: 355, abv: 5.0, quantity: 3)
        #expect(abs(triple - single * 3) < 0.001)
    }

    @Test func calculateAlcohol_zeroVolume_returnsZero() {
        let grams = BACCalculator.calculateAlcohol(volumeMl: 0, abv: 5.0, quantity: 1)
        #expect(grams == 0)
    }

    // MARK: - standardDrinks

    @Test func standardDrinks_oneUSStandardDrink() {
        // 14 g of ethanol = exactly 1 US standard drink
        #expect(abs(BACCalculator.standardDrinks(alcoholGrams: 14.0) - 1.0) < 0.001)
    }

    @Test func standardDrinks_beer355ml5pct() {
        let grams = BACCalculator.calculateAlcohol(volumeMl: 355, abv: 5.0, quantity: 1)
        let drinks = BACCalculator.standardDrinks(alcoholGrams: grams)
        #expect(abs(drinks - 1.0) < 0.05)
    }

    // MARK: - widmarkR

    @Test func widmarkR_maleHigherThanFemale() {
        #expect(BACCalculator.widmarkR(sex: .male) > BACCalculator.widmarkR(sex: .female))
    }

    @Test func widmarkR_neutralBetweenSexes() {
        let neutral = BACCalculator.widmarkR(sex: .preferNotToSay)
        #expect(neutral > BACCalculator.widmarkR(sex: .female))
        #expect(neutral < BACCalculator.widmarkR(sex: .male))
    }

    // MARK: - watsonR / forrestR

    @Test func watsonR_clamped() {
        // Extreme inputs should still produce a physiologically plausible r.
        let r = BACCalculator.watsonR(weightKg: 50, heightCm: 155, age: 25, sex: .female)
        #expect(r >= 0.50)
        #expect(r <= 0.85)
    }

    @Test func watsonR_heavierPersonLowerR() {
        // More adipose tissue relative to TBW → lower r.
        let rLight = BACCalculator.watsonR(weightKg: 55, heightCm: 170, age: 30, sex: .male)
        let rHeavy = BACCalculator.watsonR(weightKg: 120, heightCm: 170, age: 30, sex: .male)
        #expect(rLight > rHeavy)
    }

    // MARK: - eliminationRate

    @Test func eliminationRate_femaleHigherThanMale() {
        #expect(BACCalculator.eliminationRate(sex: .female) > BACCalculator.eliminationRate(sex: .male))
    }

    @Test func eliminationRate_ageOver60_slowsElimination() {
        var young = UserProfile(); young.sex = .male; young.birthYear = 1995
        var old   = UserProfile(); old.sex   = .male; old.birthYear   = 1955
        #expect(BACCalculator.eliminationRate(profile: old) < BACCalculator.eliminationRate(profile: young))
    }

    // MARK: - estimateBAC (legacy Widmark)

    @Test func estimateBAC_zeroAlcohol_returnsZero() {
        let bac = BACCalculator.estimateBAC(alcoholGrams: 0, weightKg: 70, sex: .male, durationHours: 1)
        #expect(bac == 0)
    }

    @Test func estimateBAC_heavierPersonLowerBAC() {
        let light = BACCalculator.estimateBAC(alcoholGrams: 28, weightKg: 60, sex: .male, durationHours: 0)
        let heavy = BACCalculator.estimateBAC(alcoholGrams: 28, weightKg: 90, sex: .male, durationHours: 0)
        #expect(light > heavy)
    }

    @Test func estimateBAC_femaleHigherThanMale_sameWeight() {
        // Female has lower r → higher BAC for same dose.
        let male   = BACCalculator.estimateBAC(alcoholGrams: 28, weightKg: 70, sex: .male,   durationHours: 0)
        let female = BACCalculator.estimateBAC(alcoholGrams: 28, weightKg: 70, sex: .female, durationHours: 0)
        #expect(female > male)
    }

    @Test func estimateBAC_decaysOverTime() {
        let early = BACCalculator.estimateBAC(alcoholGrams: 28, weightKg: 70, sex: .male, durationHours: 0)
        let later = BACCalculator.estimateBAC(alcoholGrams: 28, weightKg: 70, sex: .male, durationHours: 2)
        #expect(later < early)
    }

    @Test func estimateBAC_neverNegative() {
        let bac = BACCalculator.estimateBAC(alcoholGrams: 14, weightKg: 70, sex: .male, durationHours: 24)
        #expect(bac >= 0)
    }

    // MARK: - hoursToZeroBAC

    @Test func hoursToZeroBAC_positiveBAC() {
        let hours = BACCalculator.hoursToZeroBAC(0.08, sex: .male)
        #expect(hours > 0)
    }

    @Test func hoursToZeroBAC_zeroBAC_returnsZero() {
        #expect(BACCalculator.hoursToZeroBAC(0, sex: .male) == 0)
    }

    // MARK: - uncertaintyBand

    @Test func uncertaintyBand_symmetricAroundPoint() {
        let (low, high) = BACCalculator.uncertaintyBand(point: 0.08)
        let midpoint = (low + high) / 2
        #expect(abs(midpoint - 0.08) < 0.001)
    }

    @Test func uncertaintyBand_zeroInput_returnsZero() {
        let (low, high) = BACCalculator.uncertaintyBand(point: 0)
        #expect(low == 0 && high == 0)
    }

    // MARK: - getBACStatus

    @Test func getBACStatus_aboveLimit_isRed() {
        #expect(BACCalculator.getBACStatus(bac: 0.09, limit: 0.08) == .red)
    }

    @Test func getBACStatus_atLimit_isRed() {
        #expect(BACCalculator.getBACStatus(bac: 0.08, limit: 0.08) == .red)
    }

    @Test func getBACStatus_nearLimit_isAmber() {
        // 0.065 is 81.25% of limit 0.08 → amber zone (≥80%)
        #expect(BACCalculator.getBACStatus(bac: 0.065, limit: 0.08) == .amber)
    }

    @Test func getBACStatus_well_belowLimit_isGreen() {
        #expect(BACCalculator.getBACStatus(bac: 0.02, limit: 0.08) == .green)
    }

    // MARK: - currentBAC / bacTimeline (integration)

    @Test func currentBAC_noEntries_returnsZero() {
        var profile = UserProfile(); profile.weightKg = 70; profile.sex = .male
        let bac = BACCalculator.currentBAC(
            entries: [], waterEntries: [], drinkTypes: [],
            profile: profile, eventStart: Date()
        )
        #expect(bac == 0)
    }

    @Test func currentBAC_drinkLongAgo_approachesZero() {
        var profile = UserProfile(); profile.weightKg = 70; profile.sex = .male
        let drinkType = DrinkType.presets.first(where: { $0.id == "beer" })!
        let longAgo = Date().addingTimeInterval(-10 * 3600)
        let drink = DrinkEntry(
            id: "d1", eventId: "e", drinkTypeId: "beer",
            timestamp: longAgo, quantity: 1, comment: nil,
            volumeOverrideMl: nil, abvOverride: nil
        )
        let bac = BACCalculator.currentBAC(
            entries: [drink], waterEntries: [], drinkTypes: [drinkType],
            profile: profile, eventStart: longAgo
        )
        #expect(bac == 0)
    }

    @Test func bacTimeline_emptyEntries_returnsEmpty() {
        var profile = UserProfile(); profile.weightKg = 70; profile.sex = .male
        let points = BACCalculator.bacTimeline(
            entries: [], drinkTypes: [], profile: profile, eventStart: Date()
        )
        #expect(points.isEmpty)
    }

    @Test func bacTimeline_peakIsPositive() {
        var profile = UserProfile(); profile.weightKg = 70; profile.sex = .male
        let drinkType = DrinkType.presets.first(where: { $0.id == "beer" })!
        let start = Date().addingTimeInterval(-3600)
        let drink = DrinkEntry(
            id: "d1", eventId: "e", drinkTypeId: "beer",
            timestamp: start, quantity: 3, comment: nil,
            volumeOverrideMl: nil, abvOverride: nil
        )
        let points = BACCalculator.bacTimeline(
            entries: [drink], drinkTypes: [drinkType],
            profile: profile, eventStart: start
        )
        let peak = points.map(\.bac).max() ?? 0
        #expect(peak > 0)
    }

    // MARK: - hydration (coaching only)

    @Test func hydrationLevel_noDrinks_returnsNone() {
        #expect(BACCalculator.hydrationLevel(waterEntries: [], drinkCount: 0) == .none)
    }

    @Test func hydrationLevel_noWater_returnsNone() {
        #expect(BACCalculator.hydrationLevel(waterEntries: [], drinkCount: 3) == .none)
    }

    @Test func applyHydration_doesNotAlterBAC() {
        // Water pharmacokinetically does not lower BAC.
        #expect(BACCalculator.applyHydration(bac: 0.08, ratio: 2.0) == 0.08)
    }
}
