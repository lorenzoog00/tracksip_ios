//
//  DrinkServingSizeTests.swift
//  siptrackTests
//
//  Serving-size presets (dose fidelity).
//

import Testing
@testable import SipTrack

struct DrinkServingSizeTests {

    private func type(_ id: String) -> DrinkType {
        DrinkType.presets.first { $0.id == id }!
    }

    @Test func spirits_offerSingleDoubleTriple() {
        let opts = type("vodka").servingSizeOptions
        #expect(opts.count == 3)
        #expect(opts.contains { $0.label == "Double" && abs($0.volumeMl - 88) < 0.1 })
        #expect(opts.first?.label == "Single")
    }

    @Test func wine_offersSmallStandardLarge() {
        let opts = type("red-wine").servingSizeOptions
        #expect(opts.contains { $0.label == "Large" })
        #expect(opts.contains { $0.label == "Standard" })
    }

    @Test func beer_offersPint() {
        #expect(type("beer").servingSizeOptions.contains { $0.label == "Pint" })
    }

    @Test func standardOption_matchesDefaultVolume() {
        // Every category includes its standard pour = the type's default volume.
        let beer = type("beer")
        #expect(beer.servingSizeOptions.contains { abs($0.volumeMl - beer.defaultVolumeMl) < 0.1 })
    }

    @Test func calories_standardPourMatchesServingValue() {
        let beer = type("beer")
        #expect(abs(beer.calories(volumeMl: beer.defaultVolumeMl, quantity: 1) - beer.caloriesPerServing) < 0.001)
    }

    @Test func calories_scaleWithPourSize() {
        let beer = type("beer")
        let pint = beer.servingSizeOptions.first { $0.label == "Pint" }!
        let bottle = beer.calories(volumeMl: beer.defaultVolumeMl, quantity: 1)
        let asPint = beer.calories(volumeMl: pint.volumeMl, quantity: 1)
        #expect(asPint > bottle)
        #expect(abs(asPint - beer.caloriesPerServing * (pint.volumeMl / beer.defaultVolumeMl)) < 0.001)
    }

    @Test func calories_doubleShotCountsTwice() {
        let vodka = type("vodka")
        let single = vodka.calories(volumeMl: 44, quantity: 1)
        let double = vodka.calories(volumeMl: 88, quantity: 1)
        #expect(abs(double - single * 2) < 0.001)
    }

    @Test func calories_multiplyByQuantity() {
        let wine = type("red-wine")
        let one = wine.calories(volumeMl: wine.defaultVolumeMl, quantity: 1)
        let three = wine.calories(volumeMl: wine.defaultVolumeMl, quantity: 3)
        #expect(abs(three - one * 3) < 0.001)
    }
}
