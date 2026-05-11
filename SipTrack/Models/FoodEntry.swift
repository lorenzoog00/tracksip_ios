import Foundation

enum StomachState: String, Codable {
    case empty, snack, fullMeal

    var displayName: String {
        switch self {
        case .empty:    return "Empty"
        case .snack:    return "Snack"
        case .fullMeal: return "Full Meal"
        }
    }

    var emoji: String {
        switch self {
        case .empty:    return "💨"
        case .snack:    return "🥨"
        case .fullMeal: return "🍽️"
        }
    }
}

struct FoodEntry: Codable, Identifiable, Hashable {
    var id: String
    var eventId: String
    var type: StomachState   // .snack or .fullMeal — .empty is never logged
    var timestamp: Date
}
