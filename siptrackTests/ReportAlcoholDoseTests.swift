import Foundation
import Testing
@testable import siptrack

@MainActor
struct ReportAlcoholDoseTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func twoLitersOfVodkaIsOneServingAndOver45StandardDrinks() throws {
        let dose = ReportAlcoholDose(entries: [vodka("bottle", volume: 2000)], drinkTypes: DrinkType.presets)
        #expect(dose.loggedServings == 1)
        #expect(abs(dose.grams - 631.2) < 0.0001)
        #expect(abs(dose.standardDrinks - 45.085714) < 0.0001)
        let fields = try #require(dose.fields()["alcoholDose"] as? [String: Any])
        let largest = try #require(fields["largestEntry"] as? [String: Any])
        #expect(largest["volumeMlPerServing"] as? Double == 2000)
        #expect(largest["abv"] as? Double == 40)
        #expect(largest["quantity"] as? Int == 1)
    }

    @Test func sizeAbvAndQuantityDeterminePaceAndGrouping() throws {
        let entries = [
            vodka("regular", quantity: 2),
            vodka("diluted", volume: 500, abv: 20, minute: 25),
            vodka("later", volume: 100, abv: 10, minute: 80),
        ]
        let dose = ReportAlcoholDose(entries: entries, drinkTypes: DrinkType.presets)
        let fields = dose.fields(start: start, end: start.addingTimeInterval(7200))
        let groups = try #require(fields["drinks"] as? [[String: Any]])
        let summary = try #require(fields["alcoholDose"] as? [String: Any])
        #expect(groups.count == 3)
        #expect(groups.first?["abv"] as? Double == 20)
        #expect(abs(dose.grams - 114.5628) < 0.0001)
        let hourly = try #require(summary["standardDrinksPerHour"] as? Double)
        let strongest = try #require(summary["strongestHourStandardDrinks"] as? Double)
        #expect(abs(hourly - dose.standardDrinks / 2) < 0.0001)
        #expect(abs(strongest - (114.5628 - 7.89) / 14) < 0.0001)
    }

    @Test func omittedGroupsStillContributeToTheTotal() throws {
        let entries = (1...9).map { vodka("pour-\($0)", volume: Double($0) * 50) }
        let dose = ReportAlcoholDose(entries: entries, drinkTypes: DrinkType.presets)
        let fields = dose.fields()
        let groups = try #require(fields["drinks"] as? [[String: Any]])
        let summary = try #require(fields["alcoholDose"] as? [String: Any])
        #expect(groups.count == 6)
        #expect(summary["otherGroups"] as? Int == 3)
        let other = try #require(summary["otherGrams"] as? Double)
        #expect(abs(other - 94.68) < 0.0001)
        #expect(abs(dose.grams - 710.1) < 0.0001)
    }

    @Test func missingDoseIsDistinctFromZeroAbv() {
        var unknown = vodka("unknown", quantity: 2)
        unknown.drinkTypeId = "deleted-drink"
        let dose = ReportAlcoholDose(entries: [unknown, vodka("zero", abv: 0)], drinkTypes: DrinkType.presets)
        #expect(dose.loggedServings == 3)
        #expect(dose.missingServings == 2)
        #expect(dose.standardDrinks == 0)
    }

    private func vodka(_ id: String, quantity: Int = 1, volume: Double? = nil,
                       abv: Double? = nil, minute: Int = 0) -> DrinkEntry {
        DrinkEntry(id: id, eventId: "night", drinkTypeId: "vodka",
                   timestamp: start.addingTimeInterval(Double(minute) * 60), quantity: quantity, comment: nil,
                   volumeOverrideMl: volume, abvOverride: abv)
    }
}
