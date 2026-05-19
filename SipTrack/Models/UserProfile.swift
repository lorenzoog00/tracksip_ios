import Foundation

enum DriverType: String, Codable, CaseIterable {
    case general    = "general"
    case novice     = "novice"
    case commercial = "commercial"

    var displayName: String {
        switch self {
        case .general:    return "General"
        case .novice:     return "Novice / Learner"
        case .commercial: return "Commercial"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "car.fill"
        case .novice:     return "graduationcap.fill"
        case .commercial: return "truck.box.fill"
        }
    }

    var sub: String {
        switch self {
        case .general:    return "Standard driver licence"
        case .novice:     return "First 2–3 years; under-21 in many places"
        case .commercial: return "CDL, taxi, bus, heavy vehicle"
        }
    }
}

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
    var enabled: Bool          = true
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
}
