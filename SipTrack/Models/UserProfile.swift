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
    var hapticsEnabled: Bool                   = true
    var waterReminderIntervalMinutes: Int?     = nil
    var notifications: NotificationPreferences = NotificationPreferences()
    var disclaimerAcceptedAt: Date?
    var onboardingComplete: Bool               = false
    var subscriptionTier: SubscriptionTier     = .free
    var subscriptionPeriod: SubscriptionPeriod?
    var subscriptionStartedAt: Date?
    var liveActivityDrinkIds: [String]         = ["beer", "red-wine", "tequila"]
    var favoriteDrinkIds: [String]             = []
    var aiReportsUsedThisMonth: Int            = 0
    var aiReportMonthKey: String               = "" // format: "2026-05"
    var aiReportsEnabled: Bool?                = nil

    var isPro: Bool { subscriptionTier == .pro }

    var age: Int? {
        guard let year = birthYear else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }

    // Explicit (rather than synthesized) so the tolerant decoder below can name
    // the keys. Raw values are the property names, i.e. the on-disk JSON keys.
    // Every stored property must be listed here AND decoded in init(from:).
    private enum CodingKeys: String, CodingKey {
        case sex, weightKg, heightCm, birthYear, bacLimit, countryCode, driverType
        case countryDetectionLastDismissedCode, countryDetectionDisabled, countryDetectionDismissedAt
        case waterSuggestions, hapticsEnabled, waterReminderIntervalMinutes
        case notifications, disclaimerAcceptedAt, onboardingComplete
        case subscriptionTier, subscriptionPeriod, subscriptionStartedAt
        case liveActivityDrinkIds, favoriteDrinkIds
        case aiReportsUsedThisMonth, aiReportMonthKey, aiReportsEnabled
    }
}

// Swift's synthesized Decodable ignores property default values: a missing key
// throws keyNotFound. Adding any non-optional field would then make every
// profile saved by an older build fail to decode, and DataStore.load's `try?`
// would silently replace it with a blank UserProfile(). So decode by hand:
// start from the declared defaults, then overwrite whatever the JSON provides.
// It lives in an extension so the memberwise initializer and `UserProfile()`
// are still generated.
extension UserProfile {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sex                                 = try c.decodeIfPresent(Sex.self, forKey: .sex) ?? sex
        weightKg                            = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? weightKg
        heightCm                            = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        birthYear                           = try c.decodeIfPresent(Int.self, forKey: .birthYear)
        bacLimit                            = try c.decodeIfPresent(Double.self, forKey: .bacLimit) ?? bacLimit
        countryCode                         = try c.decodeIfPresent(String.self, forKey: .countryCode)
        driverType                          = try c.decodeIfPresent(DriverType.self, forKey: .driverType) ?? driverType
        countryDetectionLastDismissedCode   = try c.decodeIfPresent(String.self, forKey: .countryDetectionLastDismissedCode)
        countryDetectionDisabled            = try c.decodeIfPresent(Bool.self, forKey: .countryDetectionDisabled) ?? countryDetectionDisabled
        countryDetectionDismissedAt         = try c.decodeIfPresent(Date.self, forKey: .countryDetectionDismissedAt)
        waterSuggestions                    = try c.decodeIfPresent(Bool.self, forKey: .waterSuggestions) ?? waterSuggestions
        hapticsEnabled                      = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? hapticsEnabled
        waterReminderIntervalMinutes        = try c.decodeIfPresent(Int.self, forKey: .waterReminderIntervalMinutes)
        notifications                       = try c.decodeIfPresent(NotificationPreferences.self, forKey: .notifications) ?? notifications
        disclaimerAcceptedAt                = try c.decodeIfPresent(Date.self, forKey: .disclaimerAcceptedAt)
        onboardingComplete                  = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? onboardingComplete
        subscriptionTier                    = try c.decodeIfPresent(SubscriptionTier.self, forKey: .subscriptionTier) ?? subscriptionTier
        subscriptionPeriod                  = try c.decodeIfPresent(SubscriptionPeriod.self, forKey: .subscriptionPeriod)
        subscriptionStartedAt               = try c.decodeIfPresent(Date.self, forKey: .subscriptionStartedAt)
        liveActivityDrinkIds                = try c.decodeIfPresent([String].self, forKey: .liveActivityDrinkIds) ?? liveActivityDrinkIds
        favoriteDrinkIds                    = try c.decodeIfPresent([String].self, forKey: .favoriteDrinkIds) ?? favoriteDrinkIds
        aiReportsUsedThisMonth              = try c.decodeIfPresent(Int.self, forKey: .aiReportsUsedThisMonth) ?? aiReportsUsedThisMonth
        aiReportMonthKey                    = try c.decodeIfPresent(String.self, forKey: .aiReportMonthKey) ?? aiReportMonthKey
        aiReportsEnabled                    = try c.decodeIfPresent(Bool.self, forKey: .aiReportsEnabled)
    }
}
