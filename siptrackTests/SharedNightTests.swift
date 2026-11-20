//
//  SharedNightTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct SharedNightTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(end: Date? = nil) -> NightEvent {
        NightEvent(
            id: "e1", userId: "u", name: "Secret name", startTime: start, endTime: end,
            drivingMode: true, bacLimit: 0.05, notes: "private note", aiReport: nil, createdAt: start
        )
    }

    private var beer: DrinkType {
        DrinkType(
            id: "beer", name: "Beer", defaultVolumeMl: 355, defaultAbv: 5, caloriesPerServing: 150,
            isPreset: true, icon: "beer-outline"
        )
    }

    private func entry(_ id: String, minutes: Double, quantity: Int = 1, comment: String? = nil) -> DrinkEntry {
        DrinkEntry(
            id: id, eventId: "e1", drinkTypeId: "beer",
            timestamp: start.addingTimeInterval(minutes * 60), quantity: quantity,
            comment: comment, volumeOverrideMl: 500, abvOverride: 6
        )
    }

    private func points() -> [BACDataPoint] {
        [
            BACDataPoint(date: start, bac: 0),
            BACDataPoint(date: start.addingTimeInterval(1800), bac: 0.06),
            BACDataPoint(date: start.addingTimeInterval(7200), bac: 0)
        ]
    }

    private func night(
        end: Date? = nil, lastDrink: Date? = nil,
        expires: Date, samples: [Double] = [0, 0.04]
    ) -> SharedNight {
        SharedNight(
            startedAt: start, endedAt: end, lastDrinkAt: lastDrink ?? start,
            expiresAt: expires, samples: samples, drinks: []
        )
    }

    private func item(_ uid: String, _ n: SharedNight) -> FeedItem {
        FeedItem(profile: profile(uid), night: n)
    }

    private func profile(_ uid: String) -> FriendProfile {
        FriendProfile(uid: uid, username: uid, photoURL: nil, avatarColor: "#fff")
    }

    // MARK: - build

    @Test func buildSamplesAndDrinks() {
        let n = SharedNight.build(
            event: event(),
            entries: [entry("a", minutes: 0), entry("b", minutes: 30)],
            drinkTypes: [beer], points: points()
        )
        #expect(abs(n.samples[0]) < 0.001)
        #expect(n.samples.count <= 300)
        #expect(n.drinks.count == 2)
        #expect(n.drinks[0].name == "Beer")
        #expect(n.drinks[0].icon == "beer-outline")
        #expect(n.drinkCount == 2)
        #expect(n.peakBAC > 0.05)
        #expect(n.lastDrinkAt == start.addingTimeInterval(1800))
    }

    @Test func singleDrinkAtStartKeepsTheCurve() {
        let n = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0)],
            drinkTypes: [beer], points: points()
        )
        #expect(n.peakBAC > 0)
        #expect(n.samples.count > 1)
    }

    @Test func samplingStopsAtTheZeroAfterTheCurve() {
        // Zero crossing at 7200 s: samples at 0, 300, ... 7200 = 25 values.
        let n = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0)],
            drinkTypes: [beer], points: points()
        )
        #expect(n.samples.count == 25)
        #expect(n.samples.last == 0)
    }

    @Test func samplingCapsAtThreeHundred() {
        let long = [
            BACDataPoint(date: start, bac: 0),
            BACDataPoint(date: start.addingTimeInterval(3600), bac: 0.06),
            BACDataPoint(date: start.addingTimeInterval(40 * 3600), bac: 0.05)
        ]
        let n = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0)], drinkTypes: [beer], points: long
        )
        #expect(n.samples.count == 300)
    }

    @Test func openNightExpiresADayAfterLastDrink() {
        let n = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0), entry("b", minutes: 30)],
            drinkTypes: [beer], points: points()
        )
        #expect(n.endedAt == nil)
        #expect(n.expiresAt == start.addingTimeInterval(1800 + 86400))
    }

    @Test func closedNightExpiresADayAfterEnd() {
        let end = start.addingTimeInterval(3 * 3600)
        let n = SharedNight.build(
            event: event(end: end), entries: [entry("a", minutes: 0)],
            drinkTypes: [beer], points: points()
        )
        #expect(n.endedAt == end)
        #expect(n.expiresAt == end.addingTimeInterval(86400))
    }

    @Test func noDrinksLastDrinkIsStart() {
        let n = SharedNight.build(event: event(), entries: [], drinkTypes: [beer], points: [])
        #expect(n.lastDrinkAt == start)
        #expect(n.drinks.isEmpty)
        #expect(n.samples == [0])
    }

    @Test func quantityRepeatsTheDrink() {
        let n = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0, quantity: 3)],
            drinkTypes: [beer], points: points()
        )
        #expect(n.drinks.count == 3)
    }

    @Test func drinksCappedAtMostRecentHundred() {
        let many = (0..<120).map { entry("d\($0)", minutes: Double($0)) }
        let n = SharedNight.build(event: event(), entries: many, drinkTypes: [beer], points: points())
        #expect(n.drinks.count == 100)
        #expect(n.drinks.last?.at == start.addingTimeInterval(119 * 60))
        #expect(n.drinks.first?.at == start.addingTimeInterval(20 * 60))
    }

    // MARK: - bac(at:)

    @Test func bacInterpolatesBetweenSamples() {
        let n = night(expires: start.addingTimeInterval(86400), samples: [0.04, 0.06])
        #expect(abs(n.bac(at: start.addingTimeInterval(150)) - 0.05) < 1e-9)
    }

    @Test func bacIsZeroOutsideTheSamples() {
        let n = night(expires: start.addingTimeInterval(86400), samples: [0.04, 0.06])
        #expect(n.bac(at: start.addingTimeInterval(-1)) == 0)
        #expect(n.bac(at: start.addingTimeInterval(301)) == 0)
        #expect(abs(n.bac(at: start.addingTimeInterval(300)) - 0.06) < 1e-9)
    }

    // MARK: - Firestore

    @Test func firestoreDataKeysAreExact() {
        let end = start.addingTimeInterval(3 * 3600)
        let closed = SharedNight.build(
            event: event(end: end),
            entries: [entry("a", minutes: 0, comment: "secret comment")],
            drinkTypes: [beer], points: points()
        )
        let data = closed.firestoreData()
        #expect(Set(data.keys) == ["started_at", "ended_at", "last_drink_at", "expires_at", "samples", "drinks"])
        let drinks = data["drinks"] as? [[String: Any]] ?? []
        #expect(drinks.count == 1)
        for d in drinks {
            #expect(Set(d.keys) == ["name", "icon", "at"])
        }
        #expect(SharedNight(firestore: data)?.expiresAt == closed.expiresAt)

        let open = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0)], drinkTypes: [beer], points: points()
        )
        #expect(Set(open.firestoreData().keys) == ["started_at", "last_drink_at", "expires_at", "samples", "drinks"])
    }

    @Test func firestoreDataLeaksNothingPrivate() {
        let n = SharedNight.build(
            event: event(), entries: [entry("a", minutes: 0, comment: "secret comment")],
            drinkTypes: [beer], points: points()
        )
        let data = n.firestoreData()
        #expect(data["notes"] == nil)
        #expect(data["driving_mode"] == nil)
        #expect(data["bac_limit"] == nil)
    }

    @Test func firestoreRoundTrips() {
        let end = start.addingTimeInterval(3 * 3600)
        let n = SharedNight.build(
            event: event(end: end), entries: [entry("a", minutes: 0), entry("b", minutes: 30)],
            drinkTypes: [beer], points: points()
        )
        #expect(SharedNight(firestore: n.firestoreData()) == n)
    }

    @Test func initRejectsMissingFields() {
        #expect(SharedNight(firestore: [:]) == nil)
    }

    // MARK: - Untrusted friend data

    private var startMs: Double { start.timeIntervalSince1970 * 1000 }

    /// A normal friend night in Firestore form; `now` is two hours after the start.
    private func friendDoc(_ overrides: [String: Any] = [:]) -> [String: Any] {
        // firestoreData() supplies expires_at as a Firestore Timestamp.
        let base = SharedNight(
            startedAt: start, endedAt: nil, lastDrinkAt: start.addingTimeInterval(600),
            expiresAt: start.addingTimeInterval(86400), samples: [0.0, 0.02, 0.04],
            drinks: [SharedDrink(name: "Beer", icon: "beer-outline", at: start.addingTimeInterval(600))]
        )
        var data = base.firestoreData()
        for (key, value) in overrides { data[key] = value }
        return data
    }

    private var friendNow: Date { start.addingTimeInterval(7200) }

    @Test func initAcceptsANormalNight() {
        let n = SharedNight(firestore: friendDoc(["ended_at": startMs + 3_600_000]), now: friendNow)
        #expect(n != nil)
        #expect(n?.samples == [0.0, 0.02, 0.04])
        #expect(n?.drinks.count == 1)
        #expect(n?.endedAt == start.addingTimeInterval(3600))
    }

    @Test func initRejectsAbsurdOrNonFiniteTimes() {
        for bad: Double in [1e300, -1e300, .nan, .infinity, -.infinity, -1, 0] {
            #expect(SharedNight(firestore: friendDoc(["started_at": bad]), now: friendNow) == nil)
            #expect(SharedNight(firestore: friendDoc(["last_drink_at": bad]), now: friendNow) == nil)
            #expect(SharedNight(firestore: friendDoc(["ended_at": bad]), now: friendNow) == nil)
            let drinks: [[String: Any]] = [["name": "Beer", "icon": "beer-outline", "at": bad]]
            #expect(SharedNight(firestore: friendDoc(["drinks": drinks]), now: friendNow) == nil)
        }
        // More than two days past now.
        let farFuture = friendNow.timeIntervalSince1970 * 1000 + 3 * 86_400_000
        #expect(SharedNight(firestore: friendDoc(["started_at": farFuture]), now: friendNow) == nil)
    }

    @Test func initClampsInvertedTimesToTheStart() {
        // Older builds can write a last drink (or end) before the start: keep the
        // night, with the time moved up to the start.
        let early = startMs - 3_600_000
        let n = SharedNight(firestore: friendDoc(["last_drink_at": early, "ended_at": early]), now: friendNow)
        #expect(n != nil)
        #expect(n?.lastDrinkAt == start)
        #expect(n?.endedAt == start)
    }

    @Test func initRejectsNonFiniteSamplesAndClampsTheRest() {
        #expect(SharedNight(firestore: friendDoc(["samples": [0.01, Double.nan]]), now: friendNow) == nil)
        #expect(SharedNight(firestore: friendDoc(["samples": [Double.infinity]]), now: friendNow) == nil)
        let n = SharedNight(firestore: friendDoc(["samples": [-0.5, 0.03, 7.0]]), now: friendNow)
        #expect(n?.samples == [0, 0.03, 1.0])
    }

    @Test func msNeverTraps() {
        #expect(SharedNight.ms(Date(timeIntervalSince1970: 1e300)) == 0)
        #expect(SharedNight.ms(Date(timeIntervalSince1970: .nan)) == 0)
        #expect(SharedNight.ms(Date(timeIntervalSince1970: 1.5)) == 1500)
    }

    @Test func buildNeverPutsTheLastDrinkBeforeTheStart() {
        let n = SharedNight.build(
            event: event(), entries: [entry("early", minutes: -30)], drinkTypes: [beer], points: points()
        )
        #expect(n.lastDrinkAt == start)
    }

    @Test func feedMinutesNeverTrap() {
        #expect(FriendNightFormat.wholeMinutes(.nan) == 0)
        #expect(FriendNightFormat.wholeMinutes(.infinity) == 0)
        #expect(FriendNightFormat.wholeMinutes(-60) == 0)
        #expect(FriendNightFormat.wholeMinutes(150) == 2)
        #expect(FriendNightFormat.duration(1e300) == "2400h 0m")
    }

    // MARK: - FeedOrdering

    @Test func sectionsSplitLiveAndRecentAndDropExpired() {
        let now = start.addingTimeInterval(10_000)
        let live = item("live", night(expires: now.addingTimeInterval(3600)))
        let recent = item("recent", night(end: now.addingTimeInterval(-600), expires: now.addingTimeInterval(3600)))
        let expired = item("expired", night(end: now.addingTimeInterval(-90_000), expires: now.addingTimeInterval(-1)))
        let s = FeedOrdering.sections([expired, recent, live], now: now)
        #expect(s.live.map(\.profile.uid) == ["live"])
        #expect(s.recent.map(\.profile.uid) == ["recent"])
    }

    @Test func liveOrderedByLastDrinkDescending() {
        let now = start.addingTimeInterval(10_000)
        let older = item("older", night(lastDrink: now.addingTimeInterval(-3000), expires: now.addingTimeInterval(3600)))
        let newer = item("newer", night(lastDrink: now.addingTimeInterval(-100), expires: now.addingTimeInterval(3600)))
        #expect(FeedOrdering.sections([older, newer], now: now).live.map(\.profile.uid) == ["newer", "older"])
    }

    @Test func recentOrderedByEndDescending() {
        let now = start.addingTimeInterval(10_000)
        let a = item("a", night(end: now.addingTimeInterval(-5000), expires: now.addingTimeInterval(3600)))
        let b = item("b", night(end: now.addingTimeInterval(-500), expires: now.addingTimeInterval(3600)))
        #expect(FeedOrdering.sections([a, b], now: now).recent.map(\.profile.uid) == ["b", "a"])
    }

    // MARK: - Ended copies (one friend, two nights)

    private func night(startOffset: TimeInterval, end: Date? = nil, lastDrink: Date? = nil,
                       expires: Date) -> SharedNight {
        let started = start.addingTimeInterval(startOffset)
        return SharedNight(
            startedAt: started, endedAt: end, lastDrinkAt: lastDrink ?? started,
            expiresAt: expires, samples: [0, 0.04], drinks: []
        )
    }

    @Test func oneFriendLiveAndEndedNightsLandInBothSections() {
        let now = start.addingTimeInterval(30_000)
        let ended = night(startOffset: 0, end: now.addingTimeInterval(-9000), expires: now.addingTimeInterval(70_000))
        let live = night(startOffset: 25_000, expires: now.addingTimeInterval(80_000))
        let items = FeedOrdering.merge(profile: profile("f"), main: live, ended: [ended])
        let s = FeedOrdering.sections(items, now: now)
        #expect(s.live.map(\.night) == [live])
        #expect(s.recent.map(\.night) == [ended])
        #expect(s.live.map(\.profile.uid) == ["f"])
        #expect(s.recent.map(\.profile.uid) == ["f"])
    }

    @Test func mergeKeepsOneItemPerNightPreferringTheMainDoc() {
        let now = start.addingTimeInterval(30_000)
        let end = now.addingTimeInterval(-600)
        let main = night(startOffset: 0, end: end, expires: now.addingTimeInterval(3600))
        // The ended copy of the same night, older (say written before a later edit).
        var copy = main
        copy.lastDrinkAt = start.addingTimeInterval(-1)
        let earlier = night(startOffset: -50_000, end: now.addingTimeInterval(-20_000),
                            expires: now.addingTimeInterval(60_000))
        let items = FeedOrdering.merge(profile: profile("f"), main: main, ended: [copy, earlier, earlier])
        #expect(items.count == 2)
        #expect(items.first?.night == main)
        #expect(items.map(\.night).contains(earlier))
        // With no main doc the copies alone still show.
        #expect(FeedOrdering.merge(profile: profile("f"), main: nil, ended: [copy]).map(\.night) == [copy])
    }

    @Test func mergeLeavesExpiryToSections() {
        let now = start.addingTimeInterval(30_000)
        let expired = night(startOffset: 0, end: now.addingTimeInterval(-90_000), expires: now.addingTimeInterval(-1))
        let items = FeedOrdering.merge(profile: profile("f"), main: nil, ended: [expired])
        #expect(items.count == 1)
        let s = FeedOrdering.sections(items, now: now)
        #expect(s.live.isEmpty && s.recent.isEmpty)
    }

    @Test func feedItemIdIsUniquePerNight() {
        let now = start.addingTimeInterval(30_000)
        let a = item("f", night(startOffset: 0, end: now, expires: now.addingTimeInterval(3600)))
        let b = item("f", night(startOffset: 25_000, expires: now.addingTimeInterval(3600)))
        let c = item("g", night(startOffset: 0, end: now, expires: now.addingTimeInterval(3600)))
        #expect(Set([a.id, b.id, c.id]).count == 3)
        #expect(a.id == "f_\(a.night.startedAtMs)")
        #expect(a.id == a.key.id)
        #expect(a.key == NightKey(owner: "f", night: a.night))
    }

    @Test func startedAtMsMatchesTheFirestoreStartedAt() {
        let n = night(startOffset: 0.4567, expires: start.addingTimeInterval(3600))
        let written = n.firestoreData()["started_at"] as? Int64
        #expect(written == n.startedAtMs)
        #expect(n.startedAtMs == 1_700_000_000_457)
    }
}
