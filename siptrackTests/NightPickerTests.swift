import XCTest
@testable import SipTrack

final class NightPickerTests: XCTestCase {

    func test_isFavorite_falseByDefault() {
        let profile = UserProfile()
        XCTAssertFalse(profile.favoriteDrinkIds.contains("beer"))
    }

    func test_favoriteDrinkIds_roundtripsJSON() throws {
        var profile = UserProfile()
        profile.favoriteDrinkIds = ["beer", "tequila"]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.favoriteDrinkIds, ["beer", "tequila"])
    }
}
