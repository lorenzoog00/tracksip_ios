import Foundation
import Testing
@testable import siptrack

struct DrinkLookupTests {
    private func drink(
        _ id: String, _ name: String, volume: Double = 355, abv: Double = 5,
        calories: Double = 150, icon: String = "cup", minutes: Int? = nil
    ) -> DrinkType {
        DrinkType(
            id: id, name: name, defaultVolumeMl: volume, defaultAbv: abv,
            caloriesPerServing: calories, isPreset: false, icon: icon,
            colorHex: nil, defaultDrinkingDurationMinutes: minutes
        )
    }

    private var payload: [String: Any] {
        [
            "drink": [
                "name": "Mezcal", "volumeMl": 44, "abv": 42.0, "calories": 103,
                "minutes": 15, "category": "agave", "quantity": 2
            ],
            "remaining": 3
        ]
    }

    private func payload(_ changes: [String: Any?]) -> [String: Any] {
        var all = payload
        var drink = all["drink"] as! [String: Any]
        for (key, value) in changes {
            if let value { drink[key] = value } else { drink.removeValue(forKey: key) }
        }
        all["drink"] = drink
        return all
    }

    // MARK: - Query

    @Test func theQueryIsCollapsedAndBoundedBeforeSpendingACall() throws {
        #expect(try DrinkLookup.normalizedQuery("  dos   mezcales \n") == "dos mezcales")
        for bad in ["", " ", "a", "  x  ", String(repeating: "x", count: 121)] {
            #expect(throws: DrinkLookupError.tooShort) {
                try DrinkLookup.normalizedQuery(bad)
            }
        }
        #expect((try? DrinkLookup.normalizedQuery(String(repeating: "x", count: 120))) != nil)
    }

    // MARK: - Local catalog

    @Test func adrinkAlreadyInTheCatalogCostsNoLookup() {
        let catalog = [drink("1", "Mezcal"), drink("2", "House Red Wine")]
        #expect(DrinkLookup.localMatch(for: "mezcal", in: catalog)?.id == "1")
        // Accents and case must not send a repeat drink to the model.
        #expect(DrinkLookup.localMatch(for: "MEZCÁL", in: catalog)?.id == "1")
        // A leading count is part of the phrasing, not of the name.
        #expect(DrinkLookup.localMatch(for: "2 mezcal", in: catalog)?.id == "1")
        // Containment works in both directions.
        #expect(DrinkLookup.localMatch(for: "red wine", in: catalog)?.id == "2")
    }

    @Test func anExactNameWinsOverADrinkThatMerelyContainsIt() {
        let catalog = [drink("1", "Pale Ale"), drink("2", "Ale")]
        // Typing a drink's whole name is the strongest signal there is, so it
        // is not made ambiguous by a longer name containing it.
        #expect(DrinkLookup.localMatch(for: "ale", in: catalog)?.id == "2")
    }

    @Test func anAmbiguousOrAbsentMatchFallsThroughToTheModel() {
        let catalog = [drink("1", "Pale Ale"), drink("2", "Ginger Ale"), drink("3", "Rum")]
        // Nothing is named exactly "ale" and two drinks contain it. Prefilling
        // either is worse than spending a lookup.
        #expect(DrinkLookup.localMatch(for: "ale", in: catalog) == nil)
        #expect(DrinkLookup.localMatch(for: "negroni", in: catalog) == nil)
        // Too short to mean anything.
        #expect(DrinkLookup.localMatch(for: "a", in: catalog) == nil)
    }

    @Test func noSuggestedExampleIsAlreadyInTheCatalog() throws {
        // The whole point of the field is drinks the presets do not cover. An
        // example that `localMatch` answers from the catalog — "mezcal", say —
        // demonstrates the feature copying a drink the user could have tapped,
        // and teaches them it is useless. Add a preset named like an example
        // and this fails.
        #expect(!DrinkLookup.examples.isEmpty)
        for example in DrinkLookup.examples {
            #expect(DrinkLookup.localMatch(for: example, in: DrinkType.presets) == nil,
                    "“\(example)” already resolves to a preset")
            // It also has to survive the same validation the button applies.
            #expect(throws: Never.self) {
                try DrinkLookup.normalizedQuery(example)
            }
        }
    }

    @Test func everyPresetIsWithinTheBoundsALookupWouldHaveToClear() {
        // Presets ship to every user and bypass the lookup's validation
        // entirely, so nothing else would catch a typo'd pour or a duplicate
        // id. The bounds are the server's own, which keeps a hand-written
        // preset and a model-estimated drink held to one standard.
        var seen = Set<String>()
        for preset in DrinkType.presets {
            #expect(seen.insert(preset.id).inserted, "duplicate preset id \(preset.id)")
            #expect(!preset.name.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect((5.0...2000.0).contains(preset.defaultVolumeMl), "\(preset.name) volume")
            #expect((0.0...96.0).contains(preset.defaultAbv), "\(preset.name) ABV")
            #expect((0.0...2000.0).contains(preset.caloriesPerServing), "\(preset.name) calories")
            #expect((1...240).contains(preset.effectiveDrinkingMinutes), "\(preset.name) minutes")
        }
    }

    @Test func aCatalogMatchCarriesItsOwnNumbersThrough() {
        let match = drink("1", "Mezcal", volume: 44, abv: 42, calories: 103,
                          icon: "flask-outline", minutes: 15)
        let result = DrinkLookup.result(from: match, quantity: 2)
        #expect(result.name == "Mezcal")
        #expect(result.volumeMl == 44)
        #expect(result.abv == 42)
        #expect(result.calories == 103)
        #expect(result.minutes == 15)
        #expect(result.quantity == 2)
    }

    @Test func aLeadingCountIsReadAndAnythingElseMeansOne() {
        #expect(DrinkLookup.leadingCount(in: "3 mezcales") == 3)
        #expect(DrinkLookup.leadingCount(in: "mezcal") == 1)
        #expect(DrinkLookup.leadingCount(in: "dos mezcales") == 1)
        // Out of the server's range, so not a serving count.
        #expect(DrinkLookup.leadingCount(in: "99 mezcales") == 1)
        #expect(DrinkLookup.leadingCount(in: "0 mezcales") == 1)
    }

    // MARK: - Response

    @Test func awellFormedResponseIsReadFieldForField() throws {
        let (result, remaining) = try DrinkLookup.parse(payload)
        #expect(result == DrinkLookupResult(
            name: "Mezcal", volumeMl: 44, abv: 42, calories: 103,
            minutes: 15, category: "agave", quantity: 2
        ))
        #expect(remaining == 3)
    }

    @Test func aResponseOutsideTheServersOwnBoundsIsRejected() {
        // The server checks all of this too. If something gets past it, the
        // client is the last place a wrong pour can be stopped before it
        // reaches a BAC estimate.
        let bad: [[String: Any?]] = [
            ["volumeMl": 0], ["volumeMl": 2001], ["volumeMl": "44"], ["volumeMl": nil],
            ["abv": -1], ["abv": 97],
            ["calories": 2001],
            ["minutes": 0], ["minutes": 241], ["minutes": 15.5],
            ["quantity": 0], ["quantity": 21],
            ["category": "soda"], ["category": nil],
            ["name": ""], ["name": String(repeating: "x", count: 61)], ["name": nil]
        ]
        for change in bad {
            #expect(throws: DrinkLookupError.malformedResponse) {
                try DrinkLookup.parse(payload(change))
            }
        }
        #expect(throws: DrinkLookupError.malformedResponse) {
            try DrinkLookup.parse(["remaining": 3])
        }
    }

    @Test func aMissingRemainingCountIsNotAFailure() throws {
        // Pro has no per-kind ceiling for reports and may grow one here later;
        // a null allowance must not break the fill.
        let (_, remaining) = try DrinkLookup.parse(["drink": payload["drink"]!])
        #expect(remaining == nil)
    }

    @Test func wholeNumbersArriveAsIntAndAreStillAccepted() throws {
        // JSON gives 42 as Int and 42.5 as Double; both are valid ABVs.
        let (result, _) = try DrinkLookup.parse(payload(["abv": 42, "calories": 103.5]))
        #expect(result.abv == 42)
        #expect(result.calories == 103.5)
    }

    @Test func eachCategoryLandsOnItsOwnIconRatherThanTheGenericCup() {
        #expect(DrinkLookup.sfSymbol(for: "beer") == "mug.fill")
        #expect(DrinkLookup.sfSymbol(for: "wine") == "wineglass.fill")
        #expect(DrinkLookup.sfSymbol(for: "spirits") == "flask")
        #expect(DrinkLookup.sfSymbol(for: "agave") == "flask.fill")
        #expect(DrinkLookup.sfSymbol(for: "cocktails") == "cup.and.saucer.fill")
        // Every category the server can send must have an icon.
        #expect(Set(DrinkLookup.categories.map(DrinkLookup.sfSymbol(for:))).count == 5)
    }
}
