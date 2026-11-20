//
//  FriendLinkTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct FriendLinkTests {
    private func name(_ s: String) -> String? {
        URL(string: s).flatMap { FriendLink.username(from: $0) }
    }

    @Test func universalLink() {
        #expect(name("https://tracksip.online/u/lorenzo") == "lorenzo")
        #expect(name("https://tracksip.online/u/lo.re_n9") == "lo.re_n9")
        #expect(name("https://www.tracksip.online/u/lorenzo") == "lorenzo")
    }

    @Test func legacyLooqsLinkStillOpens() {
        #expect(name("https://looqs.online/siptrack/u/lorenzo") == "lorenzo")
        #expect(name("https://looqs.online/u/lorenzo") == nil)
        #expect(name("https://tracksip.online/siptrack/u/lorenzo") == nil)
    }

    @Test func customScheme() {
        #expect(name("siptrack://u/lorenzo") == "lorenzo")
    }

    @Test func uppercaseIsLowercased() {
        #expect(name("https://tracksip.online/u/LoRenzo") == "lorenzo")
        #expect(name("siptrack://u/LOREN") == "loren")
    }

    @Test func trailingSlash() {
        #expect(name("https://tracksip.online/u/lorenzo/") == "lorenzo")
        #expect(name("siptrack://u/lorenzo/") == "lorenzo")
    }

    @Test func invalidCharacters() {
        #expect(name("https://tracksip.online/u/lor-enzo") == nil)
        #expect(name("https://tracksip.online/u/lor%20enzo") == nil)
        #expect(name("siptrack://u/lorenzo!") == nil)
    }

    @Test func lengthLimits() {
        #expect(name("https://tracksip.online/u/ab") == nil)
        #expect(name("https://tracksip.online/u/abc") == "abc")
        #expect(name("https://tracksip.online/u/" + String(repeating: "a", count: 20)) != nil)
        #expect(name("https://tracksip.online/u/" + String(repeating: "a", count: 21)) == nil)
    }

    @Test func otherHostsAndPaths() {
        #expect(name("https://example.com/u/lorenzo") == nil)
        #expect(name("https://tracksip.online/x/lorenzo") == nil)
        #expect(name("https://tracksip.online/u/lorenzo/extra") == nil)
        #expect(name("https://tracksip.online/u") == nil)
        #expect(name("http://tracksip.online/u/lorenzo") == nil)
        #expect(name("siptrack://camera?event=abc") == nil)
        #expect(name("siptrack://x/lorenzo") == nil)
    }

    @Test func roundTrip() {
        let url = FriendLink.shareURL(for: "lo.re_n9")
        #expect(url.absoluteString == "https://tracksip.online/u/lo.re_n9")
        #expect(FriendLink.username(from: url) == "lo.re_n9")
    }

    // MARK: - Push routes

    @Test func pushRoutes() {
        #expect(PushRoute(userInfo: ["aps": [:]]) == .friends)
        #expect(PushRoute(userInfo: ["route": "friends"]) == .friends)
        #expect(PushRoute(userInfo: ["route": "add", "username": "Ana_9"]) == .add(username: "ana_9"))
        // A malformed name never reaches the add sheet.
        #expect(PushRoute(userInfo: ["route": "add", "username": "no spaces"]) == .social)
        #expect(PushRoute(userInfo: ["route": "add"]) == .social)
        #expect(PushRoute(userInfo: ["route": "social"]) == .social)
        // Reactions, comments, replies and mentions open that night's comment sheet.
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "A", "started_at": 1700000000000])
                == .thread(owner: "A", startedAt: 1700000000000))
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "A", "started_at": 1700000000000.0])
                == .thread(owner: "A", startedAt: 1700000000000))
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "A", "started_at": Int64(1700000000000)])
                == .thread(owner: "A", startedAt: 1700000000000))
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "A", "started_at": NSNumber(value: 1700000000000)])
                == .thread(owner: "A", startedAt: 1700000000000))
        #expect(PushRoute(userInfo: ["route": "thread", "started_at": 1700000000000]) == .social)
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "", "started_at": 1700000000000]) == .social)
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "A"]) == .social)
        #expect(PushRoute(userInfo: ["route": "thread", "owner": "A", "started_at": "1700000000000"]) == .social)
    }

    // MARK: - Suggestions

    private func suggestion(_ reason: PersonSuggestion.Reason) -> PersonSuggestion {
        PersonSuggestion(
            profile: FriendProfile(uid: "u", username: "u", photoURL: nil, avatarColor: "#fff"),
            reason: reason
        )
    }

    @Test func suggestionSubtitles() {
        #expect(suggestion(.contact).subtitle == "In your contacts")
        #expect(suggestion(.mutualFriends(count: 1, via: "beto")).subtitle == "Friends with @beto")
        #expect(suggestion(.mutualFriends(count: 2, via: "beto")).subtitle == "Friends with @beto and 1 other")
        #expect(suggestion(.mutualFriends(count: 4, via: "beto")).subtitle == "Friends with @beto and 3 others")
        #expect(suggestion(.mutualFriends(count: 3, via: nil)).subtitle == "3 friends in common")
    }

    @Test func visibleSuggestionsDropMeAndBlockedPeople() {
        let people = ["me", "blocked", "ok"].map { uid in
            PersonSuggestion(
                profile: FriendProfile(uid: uid, username: uid, photoURL: nil, avatarColor: "#fff"),
                reason: .contact
            )
        }
        let shown = PersonSuggestion.visible(people, myUid: "me", blocked: ["blocked"])
        #expect(shown.map(\.id) == ["ok"])
        // Signed out: nobody is "me", blocks still apply.
        #expect(PersonSuggestion.visible(people, myUid: nil, blocked: ["blocked"]).map(\.id) == ["me", "ok"])
    }

    // MARK: - A friend's chart

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func shared(ended: Bool) -> SharedNight {
        SharedNight(
            startedAt: start,
            endedAt: ended ? start.addingTimeInterval(1500) : nil,
            lastDrinkAt: start.addingTimeInterval(300),
            expiresAt: start.addingTimeInterval(90_000),
            samples: [0, 0.03, 0.05, 0.04, 0.02, 0],
            drinks: [
                SharedDrink(name: "Beer", icon: "beer-outline", at: start.addingTimeInterval(60)),
                SharedDrink(name: "Beer", icon: "beer-outline", at: start.addingTimeInterval(120)),
                SharedDrink(name: "Tequila", icon: "flask-outline", at: start.addingTimeInterval(300)),
            ]
        )
    }

    @Test func liveFriendChartSplitsAtNow() {
        let now = start.addingTimeInterval(700)
        let data = NightBACChartData(shared: shared(ended: false), now: now)
        #expect(!data.isFinished)
        #expect(data.start == start)
        #expect(data.current.date == now)
        #expect(data.history.allSatisfy { $0.date <= now })
        #expect(data.projection.allSatisfy { $0.date >= now })
        #expect(data.end == start.addingTimeInterval(1500))
        #expect(data.hours.count == 1)
        #expect(data.hours[0].summary == "Beer ×2 · Tequila ×1")
    }

    @Test func friendChartCoversAtMost48HoursBeforeTheCut() {
        // A live night that claims to have started three years ago.
        let now = start.addingTimeInterval(3 * 365 * 86400)
        let ancient = SharedNight(
            startedAt: start, endedAt: nil, lastDrinkAt: start,
            expiresAt: now.addingTimeInterval(3600), samples: [0, 0.03, 0.05], drinks: [
                SharedDrink(name: "Beer", icon: "beer-outline", at: start.addingTimeInterval(60))
            ]
        )
        let data = NightBACChartData(shared: ancient, now: now)
        #expect(data.start == now.addingTimeInterval(-48 * 3600))
        #expect(data.history.allSatisfy { $0.date >= data.start })
        #expect(data.end.timeIntervalSince(data.start) <= 48 * 3600 + 3600)
        #expect(data.hours.isEmpty)
        #expect(data.yMax.isFinite)
    }

    @Test func endedFriendChartStopsAtClose() {
        let data = NightBACChartData(shared: shared(ended: true), now: start.addingTimeInterval(80_000))
        #expect(data.isFinished)
        #expect(data.current.date == start.addingTimeInterval(1500))
        #expect(data.history.first?.date == start)
    }
}
