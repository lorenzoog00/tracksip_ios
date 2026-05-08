import Foundation

enum ReportType: String, Codable {
    case weekly     = "weekly"
    case monthly    = "monthly"
    case comparison = "comparison"
}

struct CoachReport: Codable, Identifiable, Hashable {
    var id: String
    var type: ReportType
    var periodStart: Date
    var periodEnd: Date
    var report: String?
    var createdAt: Date
    var eventAId: String?
    var eventBId: String?
}

// MARK: - Night Recovery

enum RecoverySeverity: String, Codable {
    case mild, moderate, rough

    var label: String {
        switch self {
        case .mild:     return "MILD"
        case .moderate: return "MODERATE"
        case .rough:    return "ROUGH"
        }
    }

    var icon: String {
        switch self {
        case .mild:     return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .rough:    return "xmark.octagon.fill"
        }
    }
}

struct NightRecovery: Codable, Identifiable {
    var id: String
    var severity: RecoverySeverity
    var report: String?
    var createdAt: Date
}
