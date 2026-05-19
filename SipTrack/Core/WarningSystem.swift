import Foundation

enum WarningSeverity: String { case info, warn, danger }

enum WarningKind: String {
    case pace, calories, bacApproach, bacExceeded, stageUp
}

struct DrinkWarning: Identifiable {
    let id = UUID()
    let kind: WarningKind
    let title: String
    let message: String
    let severity: WarningSeverity
}

struct WarningContext {
    let currentBAC: Double
    let previousBAC: Double
    let drivingMode: Bool
    let bacLimit: Double
    let drinksLastHour: Int
    let totalCalories: Double
    let previousStage: IntoxicationStage
    let currentStage: IntoxicationStage
    let prefs: NotificationPreferences
    let eliminationRate: Double
}

func buildWarnings(context: WarningContext) -> [DrinkWarning] {
    var warnings: [DrinkWarning] = []

    // Driving limit crossed — always warn, even if notifications are off
    if context.drivingMode {
        let limit = context.bacLimit
        if context.previousBAC < limit && context.currentBAC >= limit {
            let hoursUntilSafe = (context.currentBAC - limit) / max(context.eliminationRate, 0.005)
            let safeDate = Date().addingTimeInterval(hoursUntilSafe * 3600)
            let tf = DateFormatter()
            tf.dateStyle = .none
            tf.timeStyle = .short
            warnings.append(DrinkWarning(
                kind: .bacExceeded,
                title: "Do Not Drive",
                message: "Your BAC (\(String(format: "%.3f", context.currentBAC))%) is over your limit. Safe to drive around \(tf.string(from: safeDate)).",
                severity: .danger
            ))
        }
    }

    guard context.prefs.enabled else { return warnings }

    if context.drinksLastHour >= context.prefs.drinksPerHour {
        warnings.append(DrinkWarning(
            kind: .pace,
            title: "Slow Down",
            message: "You've had \(context.drinksLastHour) drink\(context.drinksLastHour > 1 ? "s" : "") in the last hour.",
            severity: .warn
        ))
    }

    if context.totalCalories >= Double(context.prefs.caloriesPerNight) {
        warnings.append(DrinkWarning(
            kind: .calories,
            title: "Calorie Limit Reached",
            message: "You've reached \(Int(context.totalCalories)) calories tonight.",
            severity: .info
        ))
    }

    if context.drivingMode {
        let limit = context.bacLimit
        if context.prefs.bacApproachWarning && context.currentBAC >= limit * 0.8 && context.currentBAC < limit {
            warnings.append(DrinkWarning(
                kind: .bacApproach,
                title: "Approaching Your Limit",
                message: "Your estimated BAC (\(String(format: "%.3f", context.currentBAC))%) is nearing your driving limit.",
                severity: .warn
            ))
        }
    }

    if context.prefs.stageChangeWarning &&
       context.currentStage.name != context.previousStage.name &&
       context.currentBAC >= 0.08 {
        warnings.append(DrinkWarning(
            kind: .stageUp,
            title: "Stage Change: \(context.currentStage.name)",
            message: context.currentStage.blurb,
            severity: context.currentBAC >= 0.25 ? .danger : .warn
        ))
    }

    return warnings
}
