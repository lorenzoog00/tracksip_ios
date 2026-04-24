import Foundation

enum ChallengeType: String, Codable, CaseIterable {
    case maxDrinksPerWeek    = "max_drinks_per_week"
    case maxNightsPerMonth   = "max_nights_per_month"
    case dryWeek             = "dry_week"
    case maxDrinksPerNight   = "max_drinks_per_night"
    case maxCaloriesPerWeek  = "max_calories_per_week"

    var defaultTarget: Double {
        switch self {
        case .maxDrinksPerWeek:   return 10
        case .maxNightsPerMonth:  return 4
        case .dryWeek:            return 0
        case .maxDrinksPerNight:  return 4
        case .maxCaloriesPerWeek: return 1500
        }
    }

    var label: String {
        switch self {
        case .maxDrinksPerWeek:   return "Max drinks per week"
        case .maxNightsPerMonth:  return "Max nights per month"
        case .dryWeek:            return "Dry week"
        case .maxDrinksPerNight:  return "Max drinks per night"
        case .maxCaloriesPerWeek: return "Max calories per week"
        }
    }
}

struct Challenge: Codable, Identifiable, Hashable {
    var id: String
    var type: ChallengeType
    var target: Double
    var startDate: Date
    var endDate: Date
    var createdAt: Date
    var completed: Bool
}
