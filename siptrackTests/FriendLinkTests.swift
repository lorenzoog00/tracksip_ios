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
}
