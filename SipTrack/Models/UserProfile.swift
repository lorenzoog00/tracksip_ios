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
    var waterSuggestions: Bool                 = true
    var notifications: NotificationPreferences = NotificationPreferences()
    var disclaimerAcceptedAt: Date?
    var onboardingComplete: Bool               = false
    var subscriptionTier: SubscriptionTier     = .free
    var subscriptionPeriod: SubscriptionPeriod?
    var subscriptionStartedAt: Date?
    var liveActivityDrinkIds: [String]         = ["beer", "red-wine", "tequila", "gin-tonic"]

    var isPro: Bool { subscriptionTier == .pro }

    var age: Int? {
        guard let year = birthYear else { return nil }
        return Calendar.current.component(.year, from: Date()) - year
    }
}
