//
//  DrinkServingSizeTests.swift
//  siptrackTests
//
//  Serving-size presets (dose fidelity).
//

import Testing
@testable import siptrack

struct DrinkServingSizeTests {

    private func type(_ id: String) -> DrinkType {
        DrinkType.presets.first { $0.id == id }!
    }

    @Test func everyDrinkOffersItsStandardServingAndOneLargerServing() {
        for drink in DrinkType.presets {
            let sizes = drink.servingSizeOptions
            #expect(sizes.map(\.label) == ["Standard", "Large"])
            #expect(sizes.first?.volumeMl == drink.defaultVolumeMl)
            #expect((sizes.last?.volumeMl ?? 0) > drink.defaultVolumeMl)
        }
    }

    @Test func largeUsesTheCategoryServingSize() {
        #expect(type("vodka").servingSizeOptions.last?.volumeMl == 88)
        #expect(type("red-wine").servingSizeOptions.last?.volumeMl == 250)
        #expect(type("beer").servingSizeOptions.last?.volumeMl == 568)
        #expect(type("margarita").servingSizeOptions.last?.volumeMl == 360)
    }

    @Test func largeStaysAboveAnEditedStandardServing() {
        var beer = type("beer")
        beer.defaultVolumeMl = 710
        #expect(beer.servingSizeOptions.first?.volumeMl == 710)
        #expect((beer.servingSizeOptions.last?.volumeMl ?? 0) > 710)
    }

    @Test func calories_standardPourMatchesServingValue() {
        let beer = type("beer")
        #expect(abs(beer.calories(volumeMl: beer.defaultVolumeMl, quantity: 1) - beer.caloriesPerServing) < 0.001)
    }

    @Test func calories_scaleWithPourSize() {
        let beer = type("beer")
        let large = beer.servingSizeOptions.first { $0.label == "Large" }!
        let bottle = beer.calories(volumeMl: beer.defaultVolumeMl, quantity: 1)
        let asLarge = beer.calories(volumeMl: large.volumeMl, quantity: 1)
        #expect(asLarge > bottle)
        #expect(abs(asLarge - beer.caloriesPerServing * (large.volumeMl / beer.defaultVolumeMl)) < 0.001)
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
