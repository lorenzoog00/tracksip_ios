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

        // Whole characters only, and never more than 40 UTF-16 units, which is what the
        // rules' size() counts (emulator test "favorite_drink size counts UTF-16 code
        // units"): a flag is four units, so 10 fit.
        let flags = ProfileStats.truncated(String(repeating: "🇲🇽", count: 41))
        #expect(flags.utf16.count <= 40)
        #expect(flags == String(repeating: "🇲🇽", count: 10))
        // Accented and CJK letters are one unit each: 40 of them stay whole.
        let accented = String(repeating: "\u{E9}", count: 41)
        #expect(ProfileStats.truncated(accented) == String(repeating: "\u{E9}", count: 40))
        let cjk = String(repeating: "日", count: 41)
        #expect(ProfileStats.truncated(cjk) == String(repeating: "日", count: 40))
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

    // MARK: - Reading a friend's stats

    /// What a friend reads back is what was written, `updated_at` aside.
    @Test func firestoreRoundTrip() {
        let full = ProfileStats(
            nights: 42, avgDrinks: 3.4, avgWater: 2.1, favoriteDrink: "Tequila", memberSince: memberSince
        )
        #expect(ProfileStats(firestore: full.firestoreData(updatedAt: now)) == full)

        var noFavorite = full
        noFavorite.favoriteDrink = nil
        #expect(ProfileStats(firestore: noFavorite.firestoreData(updatedAt: now)) == noFavorite)

        // No night in the last 90 days: the averages go out as 0 and come back nil.
        let outside = compute([night(daysAgo: 120, drinks: 2, waters: 1)])
        #expect(outside.nights == 1)
        #expect(outside.avgDrinks == nil)
        #expect(ProfileStats(firestore: outside.firestoreData(updatedAt: now)) == outside)

        let empty = compute([])
        #expect(ProfileStats(firestore: empty.firestoreData(updatedAt: now)) == empty)
    }

    /// Firestore hands numbers back as NSNumber, and an older or hand-edited doc may hold
    /// Doubles; a doc without its required keys is no stats at all.
    @Test func readingStatsIsTolerant() {
        let data: [String: Any] = [
            "nights": NSNumber(value: 12.0),
            "avg_drinks": NSNumber(value: 3),
            "avg_water": 1.5,
            "member_since": NSNumber(value: Int64(1_700_000_000_000)),
            "favorite_drink": "  "
        ]
        #expect(ProfileStats(firestore: data) == ProfileStats(
            nights: 12, avgDrinks: 3, avgWater: 1.5, favoriteDrink: nil, memberSince: memberSince
        ))
        #expect(ProfileStats(firestore: ["nights": 3]) == nil)
        #expect(ProfileStats(firestore: ["member_since": 1_700_000_000_000]) == nil)
        #expect(ProfileStats(firestore: ["nights": "3", "member_since": 1_700_000_000_000]) == nil)
    }

    // MARK: - The profile screen

    /// Stats show only to a friend with nights counted; anyone else gets the locked card,
    /// whatever stats there are (none are read for them).
    @Test func profileLayoutFollowsFriendshipThenStats() {
        let counted = ProfileStats(
            nights: 3, avgDrinks: 2, avgWater: 1, favoriteDrink: "Beer", memberSince: memberSince
        )
        let noNights = ProfileStats(
            nights: 0, avgDrinks: nil, avgWater: nil, favoriteDrink: nil, memberSince: memberSince
        )
        #expect(FriendProfileView.Layout.for(isFriend: true, stats: counted) == .friendStats)
        #expect(FriendProfileView.Layout.for(isFriend: true, stats: nil) == .friendNoStats)
        #expect(FriendProfileView.Layout.for(isFriend: true, stats: noNights) == .friendNoStats)
        #expect(FriendProfileView.Layout.for(isFriend: false, stats: counted) == .locked)
        #expect(FriendProfileView.Layout.for(isFriend: false, stats: noNights) == .locked)
        #expect(FriendProfileView.Layout.for(isFriend: false, stats: nil) == .locked)
    }

    /// The line under a suggested person's header says what their row said; nothing for
    /// a contact or a profile opened from anywhere else.
    @Test func mutualLineMatchesTheSuggestedRow() {
        for reason: PersonSuggestion.Reason in [
            .mutualFriends(count: 1, via: "ana"), .mutualFriends(count: 3, via: "ana"),
            .mutualFriends(count: 1, via: nil), .mutualFriends(count: 3, via: nil)
        ] {
            #expect(FriendProfileView.mutualLine(reason) == reason.subtitle)
        }
        #expect(FriendProfileView.mutualLine(.mutualFriends(count: 1, via: "ana")) == "Friends with @ana")
        #expect(FriendProfileView.mutualLine(.mutualFriends(count: 3, via: "ana")) == "Friends with @ana and 2 others")
        #expect(FriendProfileView.mutualLine(.mutualFriends(count: 3, via: nil)) == "3 friends in common")
        #expect(FriendProfileView.mutualLine(.mutualFriends(count: 0, via: nil)) == nil)
        #expect(FriendProfileView.mutualLine(.contact) == nil)
        #expect(FriendProfileView.mutualLine(nil) == nil)
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

    /// The switch lives in the profile: on by default, kept through a save, and on for a
    /// profile saved before it existed.
    @Test func sharingIsOnByDefaultAndPersistsInTheProfile() throws {
        #expect(UserProfile().shareStatsWithFriends)

        var off = UserProfile()
        off.shareStatsWithFriends = false
        let saved = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(off))
        #expect(saved.shareStatsWithFriends == false)

        let older = try #require(#"{"sex":"Male","weightKg":70,"incognitoByDefault":true}"#.data(using: .utf8))
        let decoded = try JSONDecoder().decode(UserProfile.self, from: older)
        #expect(decoded.shareStatsWithFriends)
        #expect(decoded.incognitoByDefault)
    }

    // MARK: - Pushing the switch

    /// Every key `pushProfile` sends for `fullProfile`, the switch aside.
    private static let profileKeys: Set<String> = [
        "weight_kg", "sex", "onboarding_complete", "height_cm", "age", "disclaimer_accepted_at",
        "country_code", "country_detection_last_dismissed", "country_detection_disabled",
        "favorite_drink_ids", "ai_reports_enabled", "incognito_by_default"
    ]

    /// A profile with every optional key `pushProfile` can send set.
    private func fullProfile(sharing: Bool) -> UserProfile {
        var profile = UserProfile()
        profile.sex = .female
        profile.weightKg = 61.5
        profile.heightCm = 168
        profile.birthYear = 1998
        profile.disclaimerAcceptedAt = Date(timeIntervalSince1970: 1_700_000_000)
        profile.onboardingComplete = true
        profile.countryCode = "MX"
        profile.countryDetectionLastDismissedCode = "US"
        profile.countryDetectionDisabled = true
        profile.favoriteDrinkIds = ["beer", "tequila"]
        profile.aiReportsEnabled = true
        profile.incognitoByDefault = true
        profile.shareStatsWithFriends = sharing
        return profile
    }

    /// The other keys are sent as they were before the switch existed.
    private func expectOtherProfileKeys(_ data: [String: Any]) {
        #expect(data["weight_kg"] as? Double == 61.5)
        #expect(data["sex"] as? String == "Female")
        #expect(data["onboarding_complete"] as? Bool == true)
        #expect(data["height_cm"] as? Double == 168)
        #expect(data["age"] as? Int == Calendar.current.component(.year, from: now) - 1998)
        #expect(data["disclaimer_accepted_at"] as? Double == 1_700_000_000_000)
        #expect(data["country_code"] as? String == "MX")
        #expect(data["country_detection_last_dismissed"] as? String == "US")
        #expect(data["country_detection_disabled"] as? Bool == true)
        #expect(data["favorite_drink_ids"] as? [String] == ["beer", "tequila"])
        #expect(data["ai_reports_enabled"] as? Bool == true)
        #expect(data["incognito_by_default"] as? Bool == true)
    }

    /// Off always reaches the account, whoever pushes it.
    @Test func profilePayloadAlwaysSendsOff() {
        for explicit in [false, true] {
            let data = FirebaseManager.profilePayload(
                fullProfile(sharing: false), explicitShareStats: explicit, now: now
            )
            #expect(Set(data.keys) == Self.profileKeys.union(["share_stats_with_friends"]))
            #expect(data["share_stats_with_friends"] as? Bool == false)
            expectOtherProfileKeys(data)
        }
    }

    /// Review focus: an ordinary push runs before the pull is merged, so its "on" may be
    /// stale or the default and must not overwrite the account's off. A missing key
    /// reads as on.
    @Test func profilePayloadLeavesOutAnOnTheUserDidNotJustChoose() {
        let data = FirebaseManager.profilePayload(
            fullProfile(sharing: true), explicitShareStats: false, now: now
        )
        #expect(Set(data.keys) == Self.profileKeys)
        #expect(data["share_stats_with_friends"] == nil)
        expectOtherProfileKeys(data)
    }

    /// Turning the switch on is the one push that writes true.
    @Test func profilePayloadSendsOnWhenTheUserTurnsItOn() {
        let data = FirebaseManager.profilePayload(
            fullProfile(sharing: true), explicitShareStats: true, now: now
        )
        #expect(Set(data.keys) == Self.profileKeys.union(["share_stats_with_friends"]))
        #expect(data["share_stats_with_friends"] as? Bool == true)
        expectOtherProfileKeys(data)
    }

    /// Nothing optional set: only the keys that are always sent.
    @Test func profilePayloadOfADefaultProfile() {
        let data = FirebaseManager.profilePayload(UserProfile(), explicitShareStats: false, now: now)
        #expect(Set(data.keys) == [
            "weight_kg", "sex", "onboarding_complete", "country_detection_disabled",
            "favorite_drink_ids", "ai_reports_enabled", "incognito_by_default"
        ])
        #expect(data["ai_reports_enabled"] as? Bool == false)
        #expect(data["incognito_by_default"] as? Bool == false)
    }
}
