//
//  QuickPicksTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct QuickPicksTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let catalog = ["beer", "red-wine", "tequila", "gin-tonic", "vodka", "whisky"]

    private func ids(
        logged: [(String, TimeInterval)] = [],
        favorites: [String] = [],
        lockScreen: [String] = [],
        catalog: [String]? = nil
    ) -> [String] {
        QuickPicks.ids(
            logged: logged.map { (drinkTypeId: $0.0, timestamp: t0.addingTimeInterval($0.1)) },
            favoriteIds: favorites,
            lockScreenIds: lockScreen,
            catalogIds: catalog ?? self.catalog
        )
    }

    @Test func freshNightFallsBackToCatalogueOrder() {
        #expect(ids() == ["beer", "red-wine", "tequila"])
    }

    @Test func loggedDrinksComeFirstLatestFirst() {
        let result = ids(logged: [("vodka", 0), ("whisky", 60), ("gin-tonic", 30)])
        #expect(result == ["whisky", "gin-tonic", "vodka"])
    }

    @Test func aDrinkLoggedAgainMovesToTheFront() {
        let result = ids(logged: [("vodka", 0), ("whisky", 60), ("vodka", 120)])
        #expect(result == ["vodka", "whisky", "beer"])
    }

    @Test func favouritesThenLockScreenChoiceFillAfterLoggedDrinks() {
        let result = ids(logged: [("whisky", 0)], favorites: ["gin-tonic"], lockScreen: ["vodka", "beer"])
        #expect(result == ["whisky", "gin-tonic", "vodka"])
    }

    @Test func lockScreenChoiceKeepsTheUsersOrder() {
        // The old lock-screen code filtered the catalogue, so it showed these in
        // catalogue order (beer, tequila, vodka) instead of the order chosen.
        #expect(ids(lockScreen: ["vodka", "tequila", "beer"]) == ["vodka", "tequila", "beer"])
    }

    @Test func eachDrinkAppearsOnce() {
        let result = ids(logged: [("beer", 0)], favorites: ["beer", "vodka"], lockScreen: ["vodka", "beer"])
        #expect(result == ["beer", "vodka", "red-wine"])
    }

    @Test func deletedDrinksAreSkippedAndTheRowStillFills() {
        // A logged or chosen custom drink that no longer exists in the catalogue.
        let result = ids(logged: [("custom-gone", 0)], favorites: ["also-gone"], lockScreen: ["vodka"])
        #expect(result == ["vodka", "beer", "red-wine"])
    }

    @Test func sameSecondTiesBreakById() {
        #expect(ids(logged: [("whisky", 0), ("vodka", 0)]) == ["vodka", "whisky", "beer"])
    }

    @Test func shortCatalogueReturnsWhatExists() {
        #expect(ids(catalog: ["beer"]) == ["beer"])
        #expect(ids(catalog: []).isEmpty)
    }
}
