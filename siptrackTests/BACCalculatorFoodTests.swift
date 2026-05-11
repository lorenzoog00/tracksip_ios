//
//  BACCalculatorFoodTests.swift
//  siptrackTests
//

import XCTest
@testable import siptrack

final class BACCalculatorFoodTests: XCTestCase {

    let now = Date()

    // MARK: - computeStomachFactor

    func test_emptyStomach_returnsZeroEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .empty,
            stomachStateTimestamp: now.addingTimeInterval(-3600),
            foodEntries: []
        )
        XCTAssertEqual(result.absorptionDelayMinutes, 0, accuracy: 0.01)
        XCTAssertEqual(result.peakReductionFactor, 0, accuracy: 0.01)
    }

    func test_fullMealJustEaten_returnsFullEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: now,
            foodEntries: []
        )
        XCTAssertEqual(result.absorptionDelayMinutes, 37.5, accuracy: 0.1)
        XCTAssertEqual(result.peakReductionFactor, 0.30, accuracy: 0.01)
    }

    func test_fullMealTwoHoursAgo_effectPartiallyDecayed() {
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: twoHoursAgo,
            foodEntries: []
        )
        // decay = max(0, 1 - 120/150) = 0.2
        XCTAssertEqual(result.absorptionDelayMinutes, 37.5 * 0.2, accuracy: 0.1)
        XCTAssertEqual(result.peakReductionFactor, 0.30 * 0.2, accuracy: 0.01)
    }

    func test_fullMealOver150MinAgo_effectIsZero() {
        let oldEat = now.addingTimeInterval(-3 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: oldEat,
            foodEntries: []
        )
        XCTAssertEqual(result.absorptionDelayMinutes, 0, accuracy: 0.01)
        XCTAssertEqual(result.peakReductionFactor, 0, accuracy: 0.01)
    }

    func test_inEventSnack_overridesDecayedInitialState() {
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
        XCTAssertEqual(result.peakReductionFactor, 0.15 * 0.8, accuracy: 0.01)
    }

    func test_snackReducesBACRelativeToEmpty() {
        let profile   = makeProfile()
        let drinkType = makeDrinkType()
        // Drink was consumed 1 hour ago so currentBAC (which uses Date() internally) produces non-zero BAC
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
        // Snack should reduce BAC
        XCTAssertLessThan(snackBAC, emptyBAC)
    }

    // MARK: - Helpers

    private func makeProfile() -> UserProfile {
        var p = UserProfile()
        p.weightKg = 80
        p.sex = .male
        return p
    }

    private func makeDrinkType() -> DrinkType {
        // Use the preset beer directly from DrinkType.presets
        if let beer = DrinkType.presets.first(where: { $0.id == "beer" }) {
            return beer
        }
        // Fallback with correct DrinkType field names
        return DrinkType(
            id: "beer",
            name: "Beer",
            defaultVolumeMl: 355,
            defaultAbv: 5.0,
            caloriesPerServing: 153,
            isPreset: true,
            icon: "beer-outline"
        )
    }
}
