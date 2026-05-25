import XCTest
@testable import SipTrack

final class AIInsightsTests: XCTestCase {

    func test_drinkCategory_beer() throws {
        let beer = try XCTUnwrap(DrinkType.presets.first { $0.id == "beer" }, "Preset 'beer' not found")
        XCTAssertEqual(beer.drinkCategory, "beer")
    }

    func test_drinkCategory_lightBeer() throws {
        let lightBeer = try XCTUnwrap(DrinkType.presets.first { $0.id == "light-beer" }, "Preset 'light-beer' not found")
        XCTAssertEqual(lightBeer.drinkCategory, "beer")
    }

    func test_drinkCategory_hardSeltzer() throws {
        let seltzer = try XCTUnwrap(DrinkType.presets.first { $0.id == "hard-seltzer" }, "Preset 'hard-seltzer' not found")
        XCTAssertEqual(seltzer.drinkCategory, "beer")
    }

    func test_drinkCategory_wine() throws {
        let wine = try XCTUnwrap(DrinkType.presets.first { $0.id == "red-wine" }, "Preset 'red-wine' not found")
        XCTAssertEqual(wine.drinkCategory, "wine")
    }

    func test_drinkCategory_champagne() throws {
        let champagne = try XCTUnwrap(DrinkType.presets.first { $0.id == "champagne" }, "Preset 'champagne' not found")
        XCTAssertEqual(champagne.drinkCategory, "wine")
    }

    func test_drinkCategory_tequila() throws {
        let tequila = try XCTUnwrap(DrinkType.presets.first { $0.id == "tequila" }, "Preset 'tequila' not found")
        XCTAssertEqual(tequila.drinkCategory, "agave")
    }

    func test_drinkCategory_mezcal() throws {
        let mezcal = try XCTUnwrap(DrinkType.presets.first { $0.id == "mezcal" }, "Preset 'mezcal' not found")
        XCTAssertEqual(mezcal.drinkCategory, "agave")
    }

    func test_drinkCategory_vodka() throws {
        let vodka = try XCTUnwrap(DrinkType.presets.first { $0.id == "vodka" }, "Preset 'vodka' not found")
        XCTAssertEqual(vodka.drinkCategory, "spirits")
    }

    func test_drinkCategory_whiskey() throws {
        let whiskey = try XCTUnwrap(DrinkType.presets.first { $0.id == "whiskey" }, "Preset 'whiskey' not found")
        XCTAssertEqual(whiskey.drinkCategory, "spirits")
    }

    func test_drinkCategory_cocktails() throws {
        let margarita = try XCTUnwrap(DrinkType.presets.first { $0.id == "margarita" }, "Preset 'margarita' not found")
        XCTAssertEqual(margarita.drinkCategory, "cocktails")
    }
}
