//
//  IncognitoTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

struct IncognitoTests {
    @Test func nightEventWithoutIncognitoDecodesAsNotIncognito() throws {
        // A night saved by a build that predates the field.
        let json = """
        {"id":"e1","startTime":0,"drivingMode":false,"createdAt":0}
        """
        let event = try JSONDecoder().decode(NightEvent.self, from: Data(json.utf8))
        #expect(event.incognito == nil)
        #expect(event.isIncognito == false)
    }

    @Test func nightEventIncognitoRoundtrips() throws {
        var event = try JSONDecoder().decode(
            NightEvent.self,
            from: Data(#"{"id":"e1","startTime":0,"drivingMode":false,"createdAt":0}"#.utf8)
        )
        event.incognito = true
        let decoded = try JSONDecoder().decode(NightEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded.isIncognito == true)
    }

    @Test func userProfileWithoutIncognitoByDefaultDecodesFalse() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data("{}".utf8))
        #expect(profile.incognitoByDefault == false)
    }

    @Test func userProfileIncognitoByDefaultRoundtrips() throws {
        var profile = UserProfile()
        profile.incognitoByDefault = true
        let decoded = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded.incognitoByDefault == true)
    }

    @Test func unspecifiedIncognitoUsesProfileDefault() {
        #expect(AppState.resolveIncognito(nil, profileDefault: true) == true)
        #expect(AppState.resolveIncognito(nil, profileDefault: false) == false)
    }

    @Test func explicitIncognitoBeatsProfileDefault() {
        #expect(AppState.resolveIncognito(false, profileDefault: true) == false)
        #expect(AppState.resolveIncognito(true, profileDefault: false) == true)
    }

    @Test func cloudIncognitoWinsOverAStaleLocalCopy() {
        // Another device turned incognito on: this one must stop sharing too.
        #expect(AppState.mergedIncognito(local: nil, cloud: true) == true)
        #expect(AppState.mergedIncognito(local: false, cloud: true) == true)
        #expect(AppState.mergedIncognito(local: true, cloud: true) == true)
    }

    @Test func otherwiseTheLocalIncognitoIsKept() {
        #expect(AppState.mergedIncognito(local: true, cloud: false) == true)
        #expect(AppState.mergedIncognito(local: true, cloud: nil) == true)
        #expect(AppState.mergedIncognito(local: false, cloud: nil) == false)
        #expect(AppState.mergedIncognito(local: nil, cloud: false) == nil)
        #expect(AppState.mergedIncognito(local: nil, cloud: nil) == nil)
    }
}
