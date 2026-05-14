import Foundation

enum Sex: String, Codable, CaseIterable {
    case male            = "Male"
    case female          = "Female"
    case preferNotToSay  = "Prefer not to say"
}

enum SubscriptionTier: String, Codable {
    case free = "free"
    case pro  = "pro"
}

enum SubscriptionPeriod: String, Codable {
    case monthly  = "monthly"
    case yearly   = "yearly"
    case lifetime = "lifetime"
}

struct NotificationPreferences: Codable {
    var enabled: Bool          = false
    var drinksPerHour: Int     = 2
    var caloriesPerNight: Int  = 800
    var bacApproachWarning: Bool = true
    var stageChangeWarning: Bool = true
}

struct UserProfile: Codable {
    var sex: Sex                               = .male
    var weightKg: Double                       = 70
    var heightCm: Double?
    var birthYear: Int?
    var bacLimit: Double                       = 0.08
    var countryCode: String?                   = nil
    var driverType: DriverType                 = .general
    // Last country code the user explicitly chose to ignore on the location
    // detection sheet (i.e. tapped "Keep mine" while the detector saw this
    // country). Detection still runs on every login; the sheet stays hidden
    // for this country only — once the detector reports a different country
    // we prompt again.
    var countryDetectionLastDismissedCode: String? = nil
    var countryDetectionDisabled: Bool             = false

    // Retained for backwards compatibility with older payloads; no longer
    // gates the prompt. New code should consult `countryDetectionLastDismissedCode`.
    var countryDetectionDismissedAt: Date?         = nil
    var waterSuggestions: Bool                 = true
    var waterReminderIntervalMinutes: Int?     = nil
    var notifications: NotificationPreferences = NotificationPreferences()
    var disclaimerAcceptedAt: Date?
    var onboardingComplete: Bool               = false
    var subscriptionTier: SubscriptionTier     = .free
    var subscriptionPeriod: SubscriptionPeriod?
    var subscriptionStartedAt: Date?
    var liveActivityDrinkIds: [String]         = ["beer", "red-wine", "tequila"]
    var aiReportsUsedThisMonth: Int            = 0
    var aiReportMonthKey: String               = "" // format: "2026-05"

    var isPro: Bool { subscriptionTier == .pro }

    var age: Int? {
        guard let year = birthYear else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    // Resolved legal BAC limit from the user's country + driver tier. Falls
    // back to the manual `bacLimit` field when no country is set or the
    // country is not in our lookup.
    var legalBACLimit: LegalBACLimit? {
        LegalBACLimits.find(countryCode)
    }

    var resolvedBACLimit: Double {
        legalBACLimit?.limit(for: driverType) ?? bacLimit
    }
}
