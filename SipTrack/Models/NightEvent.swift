import Foundation

struct NightEvent: Codable, Identifiable, Hashable {
    var id: String
    var userId: String?
    var name: String?
    var startTime: Date
    var endTime: Date?
    var drivingMode: Bool
    var bacLimit: Double?
    var notes: String?
    var aiReport: String?
    var createdAt: Date

    var isActive: Bool { endTime == nil }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var displayName: String {
        name?.isEmpty == false ? name! : "Night Out"
    }
}

struct DrinkEntry: Codable, Identifiable, Hashable {
    var id: String
    var eventId: String
    var drinkTypeId: String
    var timestamp: Date
    var quantity: Int
    var comment: String?
    var volumeOverrideMl: Double?
    var abvOverride: Double?
}

struct WaterEntry: Codable, Identifiable, Hashable {
    var id: String
    var eventId: String
    var timestamp: Date
    var volumeMl: Double
}

func generateId() -> String {
    "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))"
}
