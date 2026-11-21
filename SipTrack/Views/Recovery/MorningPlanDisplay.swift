import Foundation

/// What a night's row in the summary shows, in place of the old Night Analysis
/// card (`NightAnalysisCard`).
enum MorningSummaryRow: Equatable {
    /// The night has an old night report or recovery brief: today's card, untouched.
    case oldReport
    /// It is the check-in night, but its morning time hasn't come yet.
    case tomorrowMorning
    /// It is the check-in night and the morning has come: a "Check in" button.
    case checkIn
    /// Its plan exists: the headline and a link to it.
    case plan
    /// Any other night: no card.
    case hidden

    /// The old report wins, then the plan, then the check-in.
    ///
    /// - Parameters:
    ///   - isCheckInNight: the Home card is for this night right now.
    ///   - isCheckInNightLater: it will be once its morning time comes.
    static func resolve(hasOldReport: Bool, hasPlan: Bool, isCheckInNight: Bool,
                        isCheckInNightLater: Bool) -> MorningSummaryRow {
        if hasOldReport { return .oldReport }
        if hasPlan { return .plan }
        if isCheckInNight { return .checkIn }
        if isCheckInNightLater { return .tomorrowMorning }
        return .hidden
    }
}

/// The fixed copy of the check-in and the plan, and the small rules that pick
/// it from the night, the severity and the symptoms. Pure, so it is tested
/// without the views.
enum MorningPlanDisplay {
    // MARK: - Fixed copy

    static let checkInTitle = "How are you feeling?"
    static let checkInHint = "Pick all that fit"
    static let checkInButton = "Get my plan"
    static let disclosure = "Sent to Anthropic with your night details to build your plan."
    static let tomorrowLine = "Recovery plan: tomorrow morning"
    static let dontDriveLine = "Alcohol may still be in your system. Don't drive this morning."
    static let medicalHelpLine = "Can't keep water down for hours, or confused and hard to wake? Get medical help."
    static let unavailableLine = "No plan for this one — nothing in our menu fits this morning yet."
    /// Same wording and link as the old Night Analysis card.
    static let enableAILine = "Enable AI reports in Profile to share your night data with Anthropic."

    static let planLabel = "YOUR RECOVERY PLAN"
    static let recoveryModeLabel = "YOUR MORNING · RECOVERY MODE"
    static let firstFoodTitle = "FIRST FOOD · WHEN IT STAYS DOWN"

    /// While a plan has a photo still missing, its view re-reads the plan this
    /// often, this many times (60 s in all), and then gives up and keeps the
    /// icon tile.
    static let photoPollSeconds = 5
    static let photoPollAttempts = 12

    // MARK: - Check-in

    /// `MORNING AFTER · FRIDAY NIGHT`. A night that started in the small hours
    /// (before 5 AM) belongs to the evening before.
    static func checkInLabel(nightStart: Date, calendar: Calendar = .current) -> String {
        "MORNING AFTER · \(nightWeekday(start: nightStart, calendar: calendar).uppercased()) NIGHT"
    }

    static func nightWeekday(start: Date, calendar: Calendar = .current) -> String {
        let day = calendar.component(.hour, from: start) < 5
            ? (calendar.date(byAdding: .day, value: -1, to: start) ?? start)
            : start
        let formatter = AppDates.formatter("EEEE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: day)
    }

    /// `8 drinks · mostly tequila · ended 2:40 AM · 1 water`. The top drink is
    /// left out for a single drink or when no drink type is known.
    static func recap(drinks: Int, topDrink: String?, ended: String, waters: Int) -> String {
        var parts = ["\(drinks) \(drinks == 1 ? "drink" : "drinks")"]
        if drinks > 1, let topDrink, !topDrink.isEmpty {
            parts.append("mostly \(topDrink)")
        }
        parts.append("ended \(ended)")
        parts.append(waters == 0 ? "no water" : "\(waters) water")
        return parts.joined(separator: " · ")
    }

    /// The drink type with the most servings that night, named casually; a tie
    /// goes to the one logged first. Nil when no logged type is known.
    static func topDrinkName(entries: [DrinkEntry], drinkTypes: [DrinkType]) -> String? {
        var servings: [String: Int] = [:]
        var firstLogged: [String: Date] = [:]
        for entry in entries {
            servings[entry.drinkTypeId, default: 0] += max(0, entry.quantity)
            if let seen = firstLogged[entry.drinkTypeId], seen <= entry.timestamp { continue }
            firstLogged[entry.drinkTypeId] = entry.timestamp
        }
        let best = servings.filter { $0.value > 0 }.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return (firstLogged[a.key] ?? .distantFuture) > (firstLogged[b.key] ?? .distantFuture)
        }
        guard let id = best?.key, let name = drinkTypes.first(where: { $0.id == id })?.name else { return nil }
        return casualName(name)
    }

    /// "Red Wine" reads as "red wine" mid-sentence; "IPA" stays "IPA".
    static func casualName(_ name: String) -> String {
        name.split(separator: " ").map { word -> String in
            let text = String(word)
            return text == text.capitalized ? text.lowercased() : text
        }.joined(separator: " ")
    }

    // MARK: - Plan

    /// Heavy and very heavy nights get the red "recovery mode" plan.
    static func isRecoveryMode(severity: String) -> Bool {
        severity == "heavy" || severity == "very_heavy"
    }

    static func label(severity: String) -> String {
        isRecoveryMode(severity: severity) ? recoveryModeLabel : planLabel
    }

    /// After a heavy night with nausea, breakfast becomes "first food".
    static func isFirstFood(severity: String, symptoms: [Symptom]) -> Bool {
        isRecoveryMode(severity: severity) && symptoms.contains(.nausea)
    }

    /// `BREAKFAST · AROUND 10:30`, plain `BREAKFAST` without a time, or the
    /// first-food title.
    static func breakfastTitle(when: String?, firstFood: Bool) -> String {
        if firstFood { return firstFoodTitle }
        guard let when = when?.trimmingCharacters(in: .whitespacesAndNewlines), !when.isEmpty else {
            return "BREAKFAST"
        }
        return "BREAKFAST · \(when.uppercased())"
    }

    /// "Stomach off? Plain toast and broth instead." The model writes only the
    /// alternative; a title that already asks its own question is kept as is.
    static func fallbackLine(title: String, firstFood: Bool) -> String {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("?") { return text }
        return (firstFood ? "Can't face it yet? " : "Stomach off? ") + text
    }

    /// "Hair of the dog. It just pushes the hangover to later." No second full
    /// stop when the title already ends a sentence.
    static func skipLine(title: String, why: String) -> String {
        let head = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = why.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else { return head }
        guard let last = head.last else { return tail }
        return ".!?".contains(last) ? "\(head) \(tail)" : "\(head). \(tail)"
    }

    /// The safety lines the app adds, in order. Never written by the model.
    static func safetyLines(_ safety: PlanSafety) -> [String] {
        var lines: [String] = []
        if safety.dontDrive { lines.append(dontDriveLine) }
        if safety.medicalHelp { lines.append(medicalHelpLine) }
        return lines
    }

    /// Where an item's tick lives in `UserDefaults`: by `itemId` for photo
    /// items and by title for remedies, which have no id.
    static func tickKey(eventId: String, item: String) -> String {
        "morningTick.\(eventId).\(item)"
    }

    /// True while the breakfast or an activity still has no photo.
    static func hasMissingPhotos(_ plan: MorningPlan) -> Bool {
        plan.breakfast.photoUrl == nil || plan.activities.contains { $0.photoUrl == nil }
    }
}

extension AppState {
    /// What the night summary shows for this night (`MorningSummaryRow`).
    ///
    /// "Later" asks the Home card's own question at the night's morning time, so
    /// the "tomorrow morning" line follows exactly the same rules as the card
    /// that will replace it.
    func morningSummaryRow(eventId: String, now: Date = Date()) -> MorningSummaryRow {
        guard let event = events.first(where: { $0.id == eventId }) else { return .hidden }
        let hasOldReport = event.aiReport != nil || nightRecoveries.contains { $0.id == eventId }
        let isCheckInNight = morningCheckInEventId(now: now) == eventId
        var isCheckInNightLater = false
        if !isCheckInNight, let end = event.endTime {
            let morning = MorningCheckIn.morningTime(nightEnd: end)
            isCheckInNightLater = now < morning && morningCheckInEventId(now: morning) == eventId
        }
        return .resolve(hasOldReport: hasOldReport, hasPlan: morningPlans[eventId] != nil,
                        isCheckInNight: isCheckInNight, isCheckInNightLater: isCheckInNightLater)
    }

    /// The check-in's one-line recap of the night (`MorningPlanDisplay.recap`).
    func morningRecap(for event: NightEvent) -> String {
        let nightEntries = entries.filter { $0.eventId == event.id }
        return MorningPlanDisplay.recap(
            drinks: nightEntries.reduce(0) { $0 + $1.quantity },
            topDrink: MorningPlanDisplay.topDrinkName(entries: nightEntries, drinkTypes: allDrinkTypes),
            ended: (event.endTime ?? Date()).formatted(date: .omitted, time: .shortened),
            waters: waterEntries.filter { $0.eventId == event.id }.count
        )
    }
}
