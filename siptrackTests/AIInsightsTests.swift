import XCTest
@testable import SipTrack

final class AIInsightsTests: XCTestCase {

    func test_drinkCategory_beer() {
        let beer = DrinkType.presets.first { $0.id == "beer" }!
        XCTAssertEqual(beer.drinkCategory, "beer")
    }

    func test_drinkCategory_lightBeer() {
        let beer = DrinkType.presets.first { $0.id == "light-beer" }!
        XCTAssertEqual(beer.drinkCategory, "beer")
    }

    func test_drinkCategory_wine() {
        let wine = DrinkType.presets.first { $0.id == "red-wine" }!
        XCTAssertEqual(wine.drinkCategory, "wine")
    }

    func test_drinkCategory_champagne() {
        let c = DrinkType.presets.first { $0.id == "champagne" }!
        XCTAssertEqual(c.drinkCategory, "wine")
    }

    func test_drinkCategory_tequila() {
        let t = DrinkType.presets.first { $0.id == "tequila" }!
        XCTAssertEqual(t.drinkCategory, "agave")
    }

    func test_drinkCategory_mezcal() {
        let m = DrinkType.presets.first { $0.id == "mezcal" }!
        XCTAssertEqual(m.drinkCategory, "agave")
    }

    func test_drinkCategory_vodka() {
        let v = DrinkType.presets.first { $0.id == "vodka" }!
        XCTAssertEqual(v.drinkCategory, "spirits")
    }

    func test_drinkCategory_whiskey() {
        let w = DrinkType.presets.first { $0.id == "whiskey" }!
        XCTAssertEqual(w.drinkCategory, "spirits")
    }

    func test_drinkCategory_cocktails() {
        let m = DrinkType.presets.first { $0.id == "margarita" }!
        XCTAssertEqual(m.drinkCategory, "cocktails")
    }
}
