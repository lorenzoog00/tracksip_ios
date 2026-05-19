//
//  BACCalculatorFoodTests.swift
//  siptrackTests
//

import Testing
@testable import siptrack

struct BACCalculatorFoodTests {

    let now = Date()

    // MARK: - computeStomachFactor

    @Test func emptyStomach_returnsBaselineAbsorption() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .empty,
            stomachStateTimestamp: now.addingTimeInterval(-3600),
            foodEntries: []
        )
        // Empty = maximum absorption rate, no first-pass metabolism.
        #expect(abs(result.kAPerHour - 6.0) < 0.01)
        #expect(abs(result.firstPassFraction) < 0.01)
    }

    @Test func fullMealJustEaten_returnsFullSlowdownEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: now,
            foodEntries: []
        )
        // weight = 1.0 → full effect: kA = 1.5, fpm = 0.20
        #expect(abs(result.kAPerHour - 1.5) < 0.01)
        #expect(abs(result.firstPassFraction - 0.20) < 0.01)
    }

    @Test func fullMealTwoHoursAgo_effectPartiallyDecayed() {
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: twoHoursAgo,
            foodEntries: []
        )
        // weight = max(0, 1 - 120/150) = 0.2
        // kA  = 6.0 * 0.8 + 1.5 * 0.2 = 5.1
        // fpm = 0.0 * 0.8 + 0.20 * 0.2 = 0.04
        #expect(abs(result.kAPerHour - 5.1) < 0.01)
        #expect(abs(result.firstPassFraction - 0.04) < 0.01)
    }

    @Test func fullMealOver150MinAgo_effectIsZero() {
        let oldEat = now.addingTimeInterval(-3 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: oldEat,
            foodEntries: []
        )
        // weight = max(0, 1 - 180/150) = 0 → back to empty baseline
        #expect(abs(result.kAPerHour - 6.0) < 0.01)
        #expect(abs(result.firstPassFraction) < 0.01)
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
        // Initial fullMeal fully decayed (weight=0 → kA=6.0, fpm=0.0).
        // Snack 30 min ago: weight = 1 - 30/150 = 0.8
        //   kA  = 6.0*0.2 + 3.0*0.8 = 3.6
        //   fpm = 0.0*0.2 + 0.10*0.8 = 0.08
        // computeStomachFactor picks lowest kA and highest fpm.
        #expect(abs(result.kAPerHour - 3.6) < 0.01)
        #expect(abs(result.firstPassFraction - 0.08) < 0.01)
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

    @Test func futureFoodEntry_ignoredInStomachFactor() {
        let inFiveMinutes = now.addingTimeInterval(5 * 60)
        let meal = FoodEntry(id: "2", eventId: "e", type: .fullMeal, timestamp: inFiveMinutes)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .empty,
            stomachStateTimestamp: now,
            foodEntries: [meal]
        )
        // Food entry in the future must not affect current absorption.
        #expect(abs(result.kAPerHour - 6.0) < 0.01)
        #expect(abs(result.firstPassFraction) < 0.01)
    }
}
