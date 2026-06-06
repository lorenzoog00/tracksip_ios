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
}
