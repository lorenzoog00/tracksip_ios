import XCTest
@testable import siptrack

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

    // MARK: - dominantDrinkCategory helper

    func test_dominantCategory_singleType_returnsThatType() {
        // 3 tequila entries
        let types = DrinkType.presets
        let tequila = types.first { $0.id == "tequila" }!
        let counts: [String: Int] = [tequila.drinkCategory: 3]
        XCTAssertEqual(dominantCategory(counts, total: 3), "agave")
    }

    func test_dominantCategory_mixed_returnsMixed() {
        let counts: [String: Int] = ["beer": 2, "agave": 2]
        XCTAssertEqual(dominantCategory(counts, total: 4), "mixed")
    }

    func test_dominantCategory_60percentThreshold() {
        // 3 beer out of 5 = 60% → dominant
        let counts: [String: Int] = ["beer": 3, "spirits": 2]
        XCTAssertEqual(dominantCategory(counts, total: 5), "beer")
    }

    func test_dominantCategory_60percent_picksDominantNotRunner() {
        // spirits = 3/5 = 60% → wins; beer = 40% → loses
        let counts: [String: Int] = ["beer": 2, "spirits": 3]
        XCTAssertEqual(dominantCategory(counts, total: 5), "spirits")
    }

    private func dominantCategory(_ counts: [String: Int], total: Int) -> String {
        guard !counts.isEmpty, total > 0 else { return "mixed" }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return "mixed" }
        return Double(top.value) / Double(total) >= 0.6 ? top.key : "mixed"
    }

    // MARK: - Recovery brief gating

    // A free account used to reach the model: generateRecoveryBrief checked
    // aiReportsEnabled and sign-in but never Pro, unlike generateAiReport.
    // The brief it paid for is then blurred behind the paywall in
    // NightAnalysisCard, and an 8am "Recovery Brief Ready" notification tells
    // the user to come and read it.
    func test_recoveryBrief_freeAccount_isNotRequested() {
        XCTAssertFalse(
            AppState.canRequestRecoveryBrief(
                isPro: false, aiReportsEnabled: true,
                signedIn: true, alreadyRequested: false
            ),
            "A free account must never trigger a paid recovery brief"
        )
    }

    func test_recoveryBrief_proAccount_isRequested() {
        XCTAssertTrue(
            AppState.canRequestRecoveryBrief(
                isPro: true, aiReportsEnabled: true,
                signedIn: true, alreadyRequested: false
            )
        )
    }

    func test_recoveryBrief_proButAiReportsOff_isNotRequested() {
        XCTAssertFalse(
            AppState.canRequestRecoveryBrief(
                isPro: true, aiReportsEnabled: false,
                signedIn: true, alreadyRequested: false
            ),
            "Opting out of sharing data with Anthropic must still win over Pro"
        )
    }

    func test_recoveryBrief_proButSignedOut_isNotRequested() {
        XCTAssertFalse(
            AppState.canRequestRecoveryBrief(
                isPro: true, aiReportsEnabled: true,
                signedIn: false, alreadyRequested: false
            )
        )
    }

    func test_recoveryBrief_alreadyRequested_isNotRequestedAgain() {
        XCTAssertFalse(
            AppState.canRequestRecoveryBrief(
                isPro: true, aiReportsEnabled: true,
                signedIn: true, alreadyRequested: true
            ),
            "checkAndGenerateRecoveries runs on every cloud refresh and must not re-bill"
        )
    }
}
