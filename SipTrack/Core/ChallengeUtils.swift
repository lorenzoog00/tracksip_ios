import Foundation

enum ChallengeStatus { case active, completed, failed, expired }

struct ChallengeProgress {
    let challenge: Challenge
    let current: Double
    let target: Double
    let percentage: Double
    let isOver: Bool
    let daysLeft: Int
    let status: ChallengeStatus
    let label: String
}

struct ChallengeUtils {

    static func progress(
        challenge: Challenge,
        events: [NightEvent],
        entries: [DrinkEntry],
        drinkTypes: [DrinkType]
    ) -> ChallengeProgress {
        let now = Date()
        let current = computeCurrent(challenge: challenge, events: events, entries: entries, drinkTypes: drinkTypes)
        let pct = challenge.target > 0 ? min(current / challenge.target, 2.0) : (current > 0 ? 1.0 : 0.0)
        let isOver = current > challenge.target
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: now, to: challenge.endDate).day ?? 0)

        let status: ChallengeStatus
        if now > challenge.endDate {
            status = isOver ? .failed : .completed
        } else if challenge.completed {
            status = .completed
        } else {
            status = .active
        }

        let label: String
        switch challenge.type {
        case .dryWeek:
            label = current == 0 ? "No drinks this week" : "\(Int(current)) drink\(current > 1 ? "s" : "") so far"
        default:
            label = "\(Int(current)) / \(Int(challenge.target)) \(challenge.type.label)"
        }

        return ChallengeProgress(
            challenge: challenge,
            current: current,
            target: challenge.target,
            percentage: pct,
            isOver: isOver,
            daysLeft: daysLeft,
            status: status,
            label: label
        )
    }

    private static func computeCurrent(
        challenge: Challenge,
        events: [NightEvent],
        entries: [DrinkEntry],
        drinkTypes: [DrinkType]
    ) -> Double {
        let start = challenge.startDate
        let end = challenge.endDate

        switch challenge.type {
        case .maxDrinksPerWeek, .dryWeek:
            let (ws, we) = weekBounds(for: start)
            let relevant = events.filter { $0.startTime >= ws && $0.startTime <= we }
            let ids = Set(relevant.map(\.id))
            return Double(entries.filter { ids.contains($0.eventId) }.reduce(0) { $0 + $1.quantity })

        case .maxNightsPerMonth:
            let relevant = events.filter { $0.startTime >= start && $0.startTime <= end && $0.endTime != nil }
            return Double(relevant.count)

        case .maxDrinksPerNight:
            let relevant = events.filter { $0.startTime >= start && $0.startTime <= end }
            return Double(relevant.compactMap { event -> Int? in
                let total = entries.filter { $0.eventId == event.id }.reduce(0) { $0 + $1.quantity }
                return total > 0 ? total : nil
            }.max() ?? 0)

        case .maxCaloriesPerWeek:
            let (ws, we) = weekBounds(for: start)
            let relevant = events.filter { $0.startTime >= ws && $0.startTime <= we }
            let ids = Set(relevant.map(\.id))
            let cal = entries.filter { ids.contains($0.eventId) }.reduce(0.0) { sum, e in
                let dt = drinkTypes.first { $0.id == e.drinkTypeId }
                return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
            }
            return cal
        }
    }

    static func weekBounds(for date: Date) -> (start: Date, end: Date) {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        let end = cal.date(byAdding: .day, value: 6, to: start)!
        return (start, end)
    }

    static func monthBounds(for date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return (start, end)
    }

    static func defaultEndDate(for type: ChallengeType, from start: Date = Date()) -> Date {
        switch type {
        case .maxDrinksPerWeek, .dryWeek, .maxDrinksPerNight:
            return weekBounds(for: start).end
        case .maxNightsPerMonth, .maxCaloriesPerWeek:
            return monthBounds(for: start).end
        }
    }
}
