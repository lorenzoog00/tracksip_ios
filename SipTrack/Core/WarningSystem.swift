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
    let verdictBAC: Double
}

func formatHours(_ hours: Double) -> String {
    guard hours > 0 else { return "0m" }
    let h = Int(hours)
    let m = Int((hours - Double(h)) * 60)
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

func buildWarnings(context: WarningContext) -> [DrinkWarning] {
    var warnings: [DrinkWarning] = []

    // Impairment / driving — always evaluated, even if notifications are off. Driven by the
    // conservative verdict BAC (upper band or projected peak), and never affirmative: the
    // legal limit is a prosecution line, not a safety line.
    if context.drivingMode {
        let tier = BACCalculator.impairmentTier(verdictBAC: context.verdictBAC,
                                                legalLimit: context.bacLimit)
        switch tier {
        case .overLegal:
            let hrs = BACCalculator.hoursToReduceBAC(from: context.verdictBAC,
                                                     to: context.bacLimit,
                                                     beta: context.eliminationRate)
            warnings.append(DrinkWarning(
                kind: .bacExceeded,
                title: "Do Not Drive",
                message: "Estimated BAC \(String(format: "%.3f", context.verdictBAC))% is over your legal limit. Earliest legal in ~\(formatHours(hrs)) — impairment lasts longer.",
                severity: .danger
            ))
        case .impaired:
            warnings.append(DrinkWarning(
                kind: .bacExceeded,
                title: "Do Not Drive",
                message: "Estimated BAC \(String(format: "%.3f", context.verdictBAC))% — you're impaired well before the legal limit. Don't drive.",
                severity: .danger
            ))
        case .mild:
            warnings.append(DrinkWarning(
                kind: .bacApproach,
                title: "Impairment Has Begun",
                message: "Even at \(String(format: "%.3f", context.verdictBAC))% your reaction time is affected. The app can't confirm it's safe to drive.",
                severity: .warn
            ))
        case .minimal:
            break  // never an affirmative "safe to drive"
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
