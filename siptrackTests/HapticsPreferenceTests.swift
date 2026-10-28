import Testing
import Foundation
@testable import siptrack

struct HapticsPreferenceTests {

    @Test func hapticsEnabled_defaultsToTrue() {
        #expect(UserProfile().hapticsEnabled == true)
    }

    @Test func hapticsEnabled_roundtripsJSON() throws {
        var profile = UserProfile()
        profile.hapticsEnabled = false
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded.hapticsEnabled == false)
    }

    @Test func hapticsEnabled_decodesFromProfileMissingTheKey() throws {
        // Profiles written before this field exists must still decode, defaulting to on.
        let json = #"{"sex":"Male","weightKg":70,"bacLimit":0.08}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(decoded.hapticsEnabled == true)
    }
}
