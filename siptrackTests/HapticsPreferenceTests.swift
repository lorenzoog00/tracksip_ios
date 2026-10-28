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

    // MARK: - Whole-profile persistence
    //
    // UserProfile's Codable is hand-written (see UserProfile.swift). A property that is
    // added but forgotten in CodingKeys or init(from:) is not a compile error, because
    // every property has a default: the field just quietly stops persisting. The two tests
    // below pin every property so that failure is loud.

    /// A base date; each date field gets a different offset so crossed wires are caught too.
    private var day: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    /// Every stored property set to something other than its default, so a decode that
    /// silently fell back to the default would be caught.
    private func fullyPopulatedProfile() -> UserProfile {
        var p = UserProfile()
        p.sex = .female
        p.weightKg = 82.5
        p.heightCm = 181
        p.birthYear = 1991
        p.bacLimit = 0.05
        p.countryCode = "MX"
        p.driverType = .commercial
        p.countryDetectionLastDismissedCode = "US"
        p.countryDetectionDisabled = true
        p.countryDetectionDismissedAt = day
        p.waterSuggestions = false
        p.hapticsEnabled = false
        p.waterReminderIntervalMinutes = 40
        p.notifications = NotificationPreferences(
            enabled: false,
            drinksPerHour: 5,
            caloriesPerNight: 1200,
            bacApproachWarning: false,
            stageChangeWarning: false
        )
        p.disclaimerAcceptedAt = day.addingTimeInterval(86_400)
        p.onboardingComplete = true
        p.subscriptionTier = .pro
        p.subscriptionPeriod = .yearly
        p.subscriptionStartedAt = day.addingTimeInterval(172_800)
        p.liveActivityDrinkIds = ["vodka", "gin"]
        p.favoriteDrinkIds = ["whisky"]
        p.aiReportsUsedThisMonth = 3
        p.aiReportMonthKey = "2026-10"
        p.aiReportsEnabled = true
        return p
    }

    /// Asserts every property of `fullyPopulatedProfile()` except `hapticsEnabled`, which each
    /// caller checks on its own terms.
    private func expectEveryOtherPropertyIntact(_ d: UserProfile) {
        #expect(d.sex == .female)
        #expect(d.weightKg == 82.5)
        #expect(d.heightCm == 181)
        #expect(d.birthYear == 1991)
        #expect(d.bacLimit == 0.05)
        #expect(d.countryCode == "MX")
        #expect(d.driverType == .commercial)
        #expect(d.countryDetectionLastDismissedCode == "US")
        #expect(d.countryDetectionDisabled == true)
        #expect(d.countryDetectionDismissedAt == day)
        #expect(d.waterSuggestions == false)
        #expect(d.waterReminderIntervalMinutes == 40)
        #expect(d.notifications.enabled == false)
        #expect(d.notifications.drinksPerHour == 5)
        #expect(d.notifications.caloriesPerNight == 1200)
        #expect(d.notifications.bacApproachWarning == false)
        #expect(d.notifications.stageChangeWarning == false)
        #expect(d.disclaimerAcceptedAt == day.addingTimeInterval(86_400))
        #expect(d.onboardingComplete == true)
        #expect(d.subscriptionTier == .pro)
        #expect(d.subscriptionPeriod == SubscriptionPeriod.yearly)
        #expect(d.subscriptionStartedAt == day.addingTimeInterval(172_800))
        #expect(d.liveActivityDrinkIds == ["vodka", "gin"])
        #expect(d.favoriteDrinkIds == ["whisky"])
        #expect(d.aiReportsUsedThisMonth == 3)
        #expect(d.aiReportMonthKey == "2026-10")
        #expect(d.aiReportsEnabled == true)
    }

    @Test func fullProfile_roundtripsEveryProperty() throws {
        // Fails the day a property is added to UserProfile without this test being extended,
        // which is also the day CodingKeys / init(from:) need checking.
        let storedPropertyCount = Mirror(reflecting: UserProfile()).children.count
        #expect(storedPropertyCount == 24, "UserProfile gained or lost a stored property: update fullyPopulatedProfile(), expectEveryOtherPropertyIntact(_:), CodingKeys and init(from:)")

        let data = try JSONEncoder().encode(fullyPopulatedProfile())
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)

        expectEveryOtherPropertyIntact(decoded)
        #expect(decoded.hapticsEnabled == false)
    }

    @Test func profileSavedBeforeHapticsExisted_keepsEveryOtherValue() throws {
        // The production migration shape: a real saved profile carries all the other keys and
        // lacks only `hapticsEnabled`. Built by encoding a full profile and removing that one
        // key, not hand-written, so it cannot drift from the model.
        let encoded = try JSONEncoder().encode(fullyPopulatedProfile())
        let json = try JSONSerialization.jsonObject(with: encoded)
        var object = try #require(json as? [String: Any])

        let removed = object.removeValue(forKey: "hapticsEnabled")
        #expect(removed != nil, "hapticsEnabled is no longer the encoded key name")
        #expect(object.count == 23)

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: legacy)

        // The populated profile has haptics OFF, so getting `true` back proves the default
        // was applied rather than a stored value carried over.
        #expect(decoded.hapticsEnabled == true)
        expectEveryOtherPropertyIntact(decoded)
    }
}
