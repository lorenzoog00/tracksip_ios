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
}
