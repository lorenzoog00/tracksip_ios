//
//  ProfileStatsTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct ProfileStatsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let memberSince = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    private func night(
        daysAgo: Double, drinks: Int, waters: Int = 0,
        names: [String]? = nil, incognito: Bool = false
    ) -> NightSummary {
        NightSummary(
            start: now.addingTimeInterval(-daysAgo * day), incognito: incognito,
            drinks: drinks, waters: waters,
            drinkNames: names ?? Array(repeating: "Beer", count: drinks)
        )
    }

    private func compute(_ nights: [NightSummary]) -> ProfileStats {
        ProfileStats.compute(nights: nights, memberSince: memberSince, now: now)
    }

    // MARK: - compute

    @Test func incognitoAndZeroDrinkNightsAreExcluded() {
        let stats = compute([
            night(daysAgo: 1, drinks: 4, waters: 2, names: ["Beer", "Beer", "Beer", "Beer"]),
            night(daysAgo: 2, drinks: 9, waters: 9, names: Array(repeating: "Tequila", count: 9), incognito: true),
            night(daysAgo: 3, drinks: 0, waters: 7, names: [])
        ])
        #expect(stats.nights == 1)
        #expect(stats.avgDrinks == 4)
        #expect(stats.avgWater == 2)
        #expect(stats.favoriteDrink == "Beer")
    }

    @Test func aNightExactly90DaysOldCountsAnd91DoesNot() {
        let edge = compute([night(daysAgo: 90, drinks: 2, waters: 1, names: ["Wine", "Wine"])])
        #expect(edge.nights == 1)
        #expect(edge.avgDrinks == 2)
        #expect(edge.avgWater == 1)
        #expect(edge.favoriteDrink == "Wine")

        let outside = compute([night(daysAgo: 91, drinks: 2, waters: 1, names: ["Wine", "Wine"])])
        // `nights` is all time; the averages and the favorite are the last 90 days only.
        #expect(outside.nights == 1)
        #expect(outside.avgDrinks == nil)
        #expect(outside.avgWater == nil)
        #expect(outside.favoriteDrink == nil)
    }

    @Test func averagesRoundToOneDecimal() {
        let stats = compute([
            night(daysAgo: 1, drinks: 3, waters: 1),
            night(daysAgo: 2, drinks: 4, waters: 2),
            night(daysAgo: 3, drinks: 3, waters: 2)
        ])
        #expect(stats.nights == 3)
        #expect(stats.avgDrinks == 3.3)
        #expect(stats.avgWater == 1.7)
    }

    /// Review focus: zero eligible nights has no average and never divides by zero; the
    /// card shows "No stats yet" from `nights == 0`.
    @Test func noNightsMeansNoAveragesAndNoDivisionByZero() {
        let empty = compute([])
        #expect(empty.nights == 0)
        #expect(empty.avgDrinks == nil)
        #expect(empty.avgWater == nil)
        #expect(empty.favoriteDrink == nil)
        #expect(empty.memberSince == memberSince)

        // Only nights that never count: the same as none.
        let onlyExcluded = compute([
            night(daysAgo: 1, drinks: 5, incognito: true),
            night(daysAgo: 2, drinks: 0, waters: 3, names: [])
        ])
        #expect(onlyExcluded == empty)

        let data = empty.firestoreData(updatedAt: now)
        #expect(data["nights"] as? Int == 0)
        #expect(data["avg_drinks"] as? Double == 0)
        #expect(data["avg_water"] as? Double == 0)
        #expect(data["favorite_drink"] == nil)
    }

    @Test func favoriteTieGoesToAlphabeticalOrder() {
        let names = ["Wine", "Tequila", "Wine", "Tequila", "Beer"]
        #expect(compute([night(daysAgo: 1, drinks: 5, names: names)]).favoriteDrink == "Tequila")
        #expect(compute([night(daysAgo: 1, drinks: 5, names: Array(names.reversed()))]).favoriteDrink == "Tequila")
        // Case doesn't decide the order.
        #expect(ProfileStats.favorite(in: ["beer", "Aperol"]) == "Aperol")
        // Frequency beats the alphabet.
        #expect(ProfileStats.favorite(in: ["Wine", "Wine", "Beer"]) == "Wine")
        #expect(ProfileStats.favorite(in: []) == nil)
    }

    @Test func favoriteIsCountedAcrossNightsInTheWindow() {
        let stats = compute([
            night(daysAgo: 1, drinks: 2, names: ["Beer", "Mezcal"]),
            night(daysAgo: 5, drinks: 1, names: ["Mezcal"]),
            night(daysAgo: 120, drinks: 3, names: ["Beer", "Beer", "Beer"])
        ])
        #expect(stats.favoriteDrink == "Mezcal")
    }

    @Test func a41CharacterDrinkNameIsCutTo40() {
        let long = String(repeating: "x", count: 41)
        let stats = compute([night(daysAgo: 1, drinks: 1, names: [long])])
        #expect(stats.favoriteDrink == String(repeating: "x", count: 40))
        #expect(stats.favoriteDrink?.count == 40)

        // Whole characters only, and never more than 40 code points either.
        let flags = ProfileStats.truncated(String(repeating: "🇲🇽", count: 41))
        #expect(flags.unicodeScalars.count <= 40)
        #expect(flags == String(repeating: "🇲🇽", count: 20))
    }

    // MARK: - Publishing

    /// Review focus: off never writes (the caller deletes the doc instead).
    @Test func shouldWriteOnlyWhenOnAndSomethingChanged() {
        let stats = compute([night(daysAgo: 1, drinks: 3)])
        var more = stats
        more.nights += 1

        #expect(!ProfileStatsPublisher.shouldWrite(new: stats, last: nil, enabled: false))
        #expect(!ProfileStatsPublisher.shouldWrite(new: more, last: stats, enabled: false))
        #expect(!ProfileStatsPublisher.shouldWrite(new: stats, last: stats, enabled: true))
        #expect(ProfileStatsPublisher.shouldWrite(new: more, last: stats, enabled: true))
        #expect(ProfileStatsPublisher.shouldWrite(new: stats, last: nil, enabled: true))
    }

    @Test func statsGoStaleAfterADay() {
        #expect(ProfileStatsPublisher.isStale(checkedAt: nil, now: now))
        #expect(!ProfileStatsPublisher.isStale(checkedAt: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(ProfileStatsPublisher.isStale(checkedAt: now.addingTimeInterval(-day), now: now))
    }

    /// The rules deny any other key, NSNull, or a Double where an int belongs.
    @Test func firestoreDataHasExactlyTheRuleKeysWithInts() throws {
        let stats = ProfileStats(
            nights: 12, avgDrinks: 3.5, avgWater: 2, favoriteDrink: "Beer", memberSince: memberSince
        )
        let data = stats.firestoreData(updatedAt: Date(timeIntervalSince1970: 1_790_000_000.5))
        #expect(Set(data.keys) == ["nights", "avg_drinks", "avg_water", "favorite_drink", "member_since", "updated_at"])

        let nights = try #require(data["nights"])
        let since = try #require(data["member_since"])
        let updated = try #require(data["updated_at"])
        #expect(ObjectIdentifier(type(of: nights)) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(type(of: since)) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(type(of: updated)) == ObjectIdentifier(Int.self))
        #expect(nights as? Int == 12)
        #expect(since as? Int == 1_700_000_000_000)
        #expect(updated as? Int == 1_790_000_000_500)
        #expect(data["avg_drinks"] as? Double == 3.5)
        #expect(data["avg_water"] as? Double == 2)
        #expect(data["favorite_drink"] as? String == "Beer")

        var noFavorite = stats
        noFavorite.favoriteDrink = nil
        #expect(Set(noFavorite.firestoreData(updatedAt: now).keys) == ["nights", "avg_drinks", "avg_water", "member_since", "updated_at"])
    }

    @Test func firestoreDataStaysInsideTheRuleRanges() {
        let huge = ProfileStats(
            nights: 200_000, avgDrinks: 150, avgWater: -1, favoriteDrink: nil, memberSince: memberSince
        )
        let data = huge.firestoreData(updatedAt: now)
        #expect(data["nights"] as? Int == 100_000)
        #expect(data["avg_drinks"] as? Double == 100)
        #expect(data["avg_water"] as? Double == 0)
    }

    // MARK: - Building nights from the app's data

    /// Servings count each entry's quantity and carry its type's name (presets and custom
    /// types); one water entry is one glass. Running nights and other accounts' nights are
    /// left out; incognito nights are kept but flagged.
    @Test func summariesCountServingsAndGlasses() throws {
        let start = now.addingTimeInterval(-2 * day)
        func event(_ id: String, user: String = "u", ended: Bool = true, incognito: Bool? = nil) -> NightEvent {
            NightEvent(
                id: id, userId: user, name: nil, startTime: start,
                endTime: ended ? start.addingTimeInterval(3600) : nil,
                drivingMode: false, bacLimit: nil, notes: nil, aiReport: nil,
                createdAt: start, incognito: incognito
            )
        }
        func entry(_ id: String, _ eventId: String, _ typeId: String, quantity: Int = 1) -> DrinkEntry {
            DrinkEntry(
                id: id, eventId: eventId, drinkTypeId: typeId, timestamp: start,
                quantity: quantity, comment: nil, volumeOverrideMl: nil, abvOverride: nil
            )
        }
        let types = [
            DrinkType(id: "beer", name: "Beer", defaultVolumeMl: 355, defaultAbv: 5,
                      caloriesPerServing: 150, isPreset: true, icon: "beer-outline"),
            DrinkType(id: "custom-1", name: " Mezcal ", defaultVolumeMl: 45, defaultAbv: 40,
                      caloriesPerServing: 100, isPreset: false, icon: "wine-outline")
        ]
        let summaries = NightSummary.summaries(
            events: [event("e1"), event("running", ended: false), event("theirs", user: "x"),
                     event("hidden", incognito: true)],
            entries: [
                entry("d1", "e1", "beer", quantity: 2),
                entry("d2", "e1", "custom-1"),
                entry("d3", "e1", "deleted-type"),
                entry("d4", "running", "beer"),
                entry("d5", "hidden", "beer")
            ],
            waterEntries: (1...3).map { WaterEntry(id: "w\($0)", eventId: "e1", timestamp: start, volumeMl: 250) },
            drinkTypes: types,
            userId: "u"
        )

        #expect(summaries.count == 2)
        let first = try #require(summaries.first)
        #expect(first.start == start)
        #expect(!first.incognito)
        #expect(first.drinks == 4)
        #expect(first.waters == 3)
        #expect(first.drinkNames.sorted() == ["Beer", "Beer", "Mezcal"])

        let hidden = try #require(summaries.last)
        #expect(hidden.incognito)
        #expect(hidden.drinks == 1)
        #expect(hidden.waters == 0)
    }

    // MARK: - The switch

    @Test func sharingIsOnByDefaultAndRememberedPerAccount() {
        let uid = "profile-stats-test-\(UUID().uuidString)"
        let otherUid = "profile-stats-test-\(UUID().uuidString)"
        defer { ProfileStatsSharing.clear(uid: uid) }

        #expect(ProfileStatsSharing.isOn(uid: uid))
        ProfileStatsSharing.set(false, uid: uid)
        #expect(!ProfileStatsSharing.isOn(uid: uid))
        #expect(ProfileStatsSharing.isOn(uid: otherUid))
        ProfileStatsSharing.set(true, uid: uid)
        #expect(ProfileStatsSharing.isOn(uid: uid))
        ProfileStatsSharing.set(false, uid: uid)
        ProfileStatsSharing.clear(uid: uid)
        #expect(ProfileStatsSharing.isOn(uid: uid))
    }
}
