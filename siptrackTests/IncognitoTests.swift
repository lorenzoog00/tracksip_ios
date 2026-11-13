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
}
