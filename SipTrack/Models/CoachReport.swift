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
