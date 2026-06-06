import XCTest
@testable import SipTrack

final class NightPickerTests: XCTestCase {

    func test_favoriteDrinkIds_emptyByDefault() {
        XCTAssertTrue(UserProfile().favoriteDrinkIds.isEmpty)
    }

    func test_favoriteDrinkIds_roundtripsJSON() throws {
        var profile = UserProfile()
        profile.favoriteDrinkIds = ["beer", "tequila"]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.favoriteDrinkIds, ["beer", "tequila"])
    }

    func test_toggleFavoriteDrink_addsAndRemovesId() {
        var profile = UserProfile()
        // Add
        if !profile.favoriteDrinkIds.contains("beer") {
            profile.favoriteDrinkIds.append("beer")
        }
        XCTAssertTrue(profile.favoriteDrinkIds.contains("beer"))
        // Remove
        profile.favoriteDrinkIds.removeAll { $0 == "beer" }
        XCTAssertFalse(profile.favoriteDrinkIds.contains("beer"))
    }

    // MARK: - computeNightFacts tests

    func test_computeFacts_soberNight() {
        let facts = computeNightFacts(
            drinkCount: 0, waterCount: 0, currentBAC: 0, bacLimit: 0.08,
            hoursElapsed: 2, totalCalories: 0, peakBAC: 0, peakBACMinutesAgo: 0,
            drinksThisHour: 0, avgDrinksPerHour: 0
        )
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(facts[0].text.contains("Sober"))
    }

    func test_computeFacts_approachingLimit() {
        let facts = computeNightFacts(
            drinkCount: 4, waterCount: 0, currentBAC: 0.07, bacLimit: 0.08,
            hoursElapsed: 2, totalCalories: 400, peakBAC: 0.07, peakBACMinutesAgo: 5,
            drinksThisHour: 1, avgDrinksPerHour: 1.5
        )
        XCTAssertTrue(facts.contains { $0.isSafetyAlert && $0.text.contains("limit") })
    }

    func test_computeFacts_maxThreeFacts() {
        let facts = computeNightFacts(
            drinkCount: 5, waterCount: 3, currentBAC: 0.06, bacLimit: 0.08,
            hoursElapsed: 2, totalCalories: 600, peakBAC: 0.07, peakBACMinutesAgo: 30,
            drinksThisHour: 4, avgDrinksPerHour: 1.5
        )
        XCTAssertLessThanOrEqual(facts.count, 3)
    }

    func test_computeFacts_hydrationFact() {
        let facts = computeNightFacts(
            drinkCount: 2, waterCount: 3, currentBAC: 0.02, bacLimit: 0.08,
            hoursElapsed: 2, totalCalories: 200, peakBAC: 0.03, peakBACMinutesAgo: 10,
            drinksThisHour: 0, avgDrinksPerHour: 1.0
        )
        XCTAssertTrue(facts.contains { $0.text.contains("water") })
    }
}
