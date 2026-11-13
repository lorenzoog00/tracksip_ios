//
//  SharedNightSyncTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: the app module defaults to MainActor isolation and this test target does not
// (see CeilingCrossingTests).
@MainActor
struct SharedNightSyncTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(incognito: Bool? = nil) -> NightEvent {
        var e = NightEvent(
            id: "e1", userId: "u", name: nil, startTime: start, endTime: nil,
            drivingMode: false, bacLimit: nil, notes: nil, aiReport: nil, createdAt: start
        )
        e.incognito = incognito
        return e
    }

    private func night(drinks: Int = 1, endedAt: Date? = nil) -> SharedNight {
        SharedNight(
            startedAt: start, endedAt: endedAt, lastDrinkAt: start,
            expiresAt: start.addingTimeInterval(86400), samples: [0, 0.03],
            drinks: Array(repeating: SharedDrink(name: "Beer", icon: "beer-outline", at: start), count: drinks)
        )
    }

    private func run(event: NightEvent?, night: SharedNight?, lastSent: SharedNight?, hasUsername: Bool) -> SharedNightAction {
        SharedNightSync.action(isIncognito: event?.isIncognito, night: night, lastSent: lastSent, hasUsername: hasUsername)
    }

    @Test func incognitoEventDeletes() {
        let action = run(event: event(incognito: true), night: night(), lastSent: night(), hasUsername: true)
        #expect(action == .delete)
    }

    @Test func incognitoEventNeverWritesEvenWithNewDrink() {
        let action = run(event: event(incognito: true), night: night(drinks: 2), lastSent: night(drinks: 1), hasUsername: true)
        #expect(action != .write(night(drinks: 2)))
        #expect(action == .delete)
        let none = run(event: event(incognito: true), night: night(drinks: 2), lastSent: nil, hasUsername: true)
        if case .write = none { Issue.record("incognito produced a write") }
    }

    @Test func noUsernameDoesNothing() {
        #expect(run(event: event(), night: night(), lastSent: nil, hasUsername: false) == .none)
        #expect(run(event: event(incognito: true), night: night(), lastSent: nil, hasUsername: false) == .delete)
    }

    @Test func noEventDoesNothing() {
        #expect(run(event: nil, night: nil, lastSent: nil, hasUsername: true) == .none)
    }

    @Test func unchangedNightDoesNothing() {
        #expect(run(event: event(), night: night(), lastSent: night(), hasUsername: true) == .none)
    }

    @Test func changedDrinksWrite() {
        let action = run(event: event(), night: night(drinks: 2), lastSent: night(drinks: 1), hasUsername: true)
        #expect(action == .write(night(drinks: 2)))
    }

    @Test func firstSendWrites() {
        #expect(run(event: event(), night: night(), lastSent: nil, hasUsername: true) == .write(night()))
    }

    @Test func endingTheNightWritesAgain() {
        let ended = night(endedAt: start.addingTimeInterval(3600))
        let action = run(event: event(), night: ended, lastSent: night(), hasUsername: true)
        #expect(action == .write(ended))
    }

    @Test func turningIncognitoOffResendsWholeNight() {
        // After incognito on, AppState clears lastSent; off again must write.
        let action = run(event: event(incognito: false), night: night(), lastSent: nil, hasUsername: true)
        #expect(action == .write(night()))
    }
}
