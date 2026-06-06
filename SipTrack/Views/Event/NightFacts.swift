import Foundation

struct NightFact {
    let text: String
    let isSafetyAlert: Bool  // true = shown in danger/amber color
}

/// Computes 1–3 contextual facts about the current session.
/// Pure function — no side effects, no SwiftUI dependencies.
func computeNightFacts(
    drinkCount: Int,
    waterCount: Int,
    currentBAC: Double,
    bacLimit: Double,
    hoursElapsed: Double,
    totalCalories: Int,
    peakBAC: Double,
    peakBACMinutesAgo: Int,
    drinksThisHour: Int,
    avgDrinksPerHour: Double
) -> [NightFact] {
    var facts: [NightFact] = []

    // 1. Safety: approaching limit
    if currentBAC > 0 && currentBAC < bacLimit {
        let remainingBAC = bacLimit - currentBAC
        let hoursToLimit = remainingBAC / 0.018  // avg 1 drink ≈ 0.018 BAC
        if hoursToLimit < 1.5 && drinkCount > 0 {
            let mins = Int(hoursToLimit * 60)
            facts.append(NightFact(
                text: "At this pace you're ~\(mins) min from your limit.",
                isSafetyAlert: true
            ))
        }
    }

    // 2. Peak BAC dropping
    if peakBAC > 0.04 && peakBACMinutesAgo > 15 && currentBAC < peakBAC {
        facts.append(NightFact(
            text: "Your BAC peaked \(peakBACMinutesAgo) min ago — it's dropping now.",
            isSafetyAlert: false
        ))
    }

    // 3. Heavy hour
    if drinksThisHour >= 3 && drinksThisHour > Int(avgDrinksPerHour * 1.5) {
        facts.append(NightFact(
            text: "You've had \(drinksThisHour) drinks this hour — your fastest stretch tonight.",
            isSafetyAlert: true
        ))
    }

    // 4. Calorie comparison
    if facts.count < 3 && totalCalories > 300 {
        let comparison: String
        switch totalCalories {
        case 0..<250:   comparison = "a bag of chips"
        case 250..<450: comparison = "a slice of pizza"
        case 450..<700: comparison = "a cheeseburger"
        default:        comparison = "a full burger meal"
        }
        facts.append(NightFact(
            text: "You've had ~\(totalCalories) cal tonight — about the same as \(comparison).",
            isSafetyAlert: false
        ))
    }

    // 5. Hydration positive
    if facts.count < 3 && waterCount >= 2 {
        facts.append(NightFact(
            text: "\(waterCount) waters tonight — solid hydration.",
            isSafetyAlert: false
        ))
    }

    // 6. Sober night
    if drinkCount == 0 {
        facts.append(NightFact(
            text: "Sober night — your body is getting a full reset.",
            isSafetyAlert: false
        ))
    }

    return Array(facts.prefix(3))
}
