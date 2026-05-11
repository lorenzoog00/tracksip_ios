//
//  BACCalculatorFoodTests.swift
//  siptrackTests
//

import Testing
@testable import siptrack

struct BACCalculatorFoodTests {

    let now = Date()

    // MARK: - computeStomachFactor

    @Test func emptyStomach_returnsZeroEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .empty,
            stomachStateTimestamp: now.addingTimeInterval(-3600),
            foodEntries: []
        )
        #expect(abs(result.absorptionDelayMinutes) < 0.01)
        #expect(abs(result.peakReductionFactor) < 0.01)
    }

    @Test func fullMealJustEaten_returnsFullEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: now,
            foodEntries: []
        )
        #expect(abs(result.absorptionDelayMinutes - 37.5) < 0.1)
        #expect(abs(result.peakReductionFactor - 0.30) < 0.01)
    }

    @Test func fullMealTwoHoursAgo_effectPartiallyDecayed() {
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: twoHoursAgo,
            foodEntries: []
        )
        // decay = max(0, 1 - 120/150) = 0.2
        #expect(abs(result.absorptionDelayMinutes - 37.5 * 0.2) < 0.1)
        #expect(abs(result.peakReductionFactor - 0.30 * 0.2) < 0.01)
    }

    @Test func fullMealOver150MinAgo_effectIsZero() {
        let oldEat = now.addingTimeInterval(-3 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: oldEat,
            foodEntries: []
        )
        #expect(abs(result.absorptionDelayMinutes) < 0.01)
        #expect(abs(result.peakReductionFactor) < 0.01)
    }

    @Test func inEventSnack_overridesDecayedInitialState() {
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
        let thirtyMinAgo  = now.addingTimeInterval(-30 * 60)
        let snack = FoodEntry(id: "1", eventId: "e", type: .snack, timestamp: thirtyMinAgo)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: threeHoursAgo,
            foodEntries: [snack]
        )
        // Initial fullMeal is fully decayed. Snack 30 min ago: decay = 1 - 30/150 = 0.8
        #expect(abs(result.peakReductionFactor - 0.15 * 0.8) < 0.01)
    }

    @Test func snackReducesBACRelativeToEmpty() {
        var profile = UserProfile()
        profile.weightKg = 80
        profile.sex = .male

        let drinkType = DrinkType.presets.first(where: { $0.id == "beer" }) ?? DrinkType(
            id: "beer", name: "Beer", defaultVolumeMl: 355, defaultAbv: 5.0,
            caloriesPerServing: 153, isPreset: true, icon: "beer-outline"
        )
        let drinkTime = Date().addingTimeInterval(-3600)
        let drink = DrinkEntry(
            id: "d1", eventId: "e", drinkTypeId: "beer",
            timestamp: drinkTime,
            quantity: 1, comment: nil, volumeOverrideMl: nil, abvOverride: nil
        )

        let emptyBAC = BACCalculator.currentBAC(
            entries: [drink], waterEntries: [], drinkTypes: [drinkType],
            profile: profile, eventStart: drinkTime
        )
        let snackBAC = BACCalculator.currentBAC(
            entries: [drink], waterEntries: [], drinkTypes: [drinkType],
            profile: profile, eventStart: drinkTime,
            stomachState: .snack,
            stomachStateTimestamp: drinkTime,
            foodEntries: []
        )
        #expect(snackBAC < emptyBAC)
    }
}
