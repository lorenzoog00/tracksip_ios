//
//  SharedNightTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

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
        FeedItem(id: uid, profile: FriendProfile(uid: uid, username: uid, photoURL: nil, avatarColor: "#fff"), night: n)
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
        #expect(String(describing: type(of: data["expires_at"]!)) == "Timestamp")

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

    // MARK: - FeedOrdering

    @Test func sectionsSplitLiveAndRecentAndDropExpired() {
        let now = start.addingTimeInterval(10_000)
        let live = item("live", night(expires: now.addingTimeInterval(3600)))
        let recent = item("recent", night(end: now.addingTimeInterval(-600), expires: now.addingTimeInterval(3600)))
        let expired = item("expired", night(end: now.addingTimeInterval(-90_000), expires: now.addingTimeInterval(-1)))
        let s = FeedOrdering.sections([expired, recent, live], now: now)
        #expect(s.live.map(\.id) == ["live"])
        #expect(s.recent.map(\.id) == ["recent"])
    }

    @Test func liveOrderedByLastDrinkDescending() {
        let now = start.addingTimeInterval(10_000)
        let older = item("older", night(lastDrink: now.addingTimeInterval(-3000), expires: now.addingTimeInterval(3600)))
        let newer = item("newer", night(lastDrink: now.addingTimeInterval(-100), expires: now.addingTimeInterval(3600)))
        #expect(FeedOrdering.sections([older, newer], now: now).live.map(\.id) == ["newer", "older"])
    }

    @Test func recentOrderedByEndDescending() {
        let now = start.addingTimeInterval(10_000)
        let a = item("a", night(end: now.addingTimeInterval(-5000), expires: now.addingTimeInterval(3600)))
        let b = item("b", night(end: now.addingTimeInterval(-500), expires: now.addingTimeInterval(3600)))
        #expect(FeedOrdering.sections([a, b], now: now).recent.map(\.id) == ["b", "a"])
    }
}
