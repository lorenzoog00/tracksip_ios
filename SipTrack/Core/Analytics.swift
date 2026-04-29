import Foundation

struct PeriodStats {
    var label: String
    var from: Date
    var to: Date
    var totalEvents: Int          = 0
    var totalDrinks: Int          = 0
    var avgDrinksPerNight: Double = 0
    var totalCalories: Double     = 0
    var totalAlcoholG: Double     = 0
    var drinksByType: [(name: String, count: Int)] = []
    var dayOfWeekAvg: [String: Double]             = [:]
}

struct AllTimeStats {
    var totalEvents: Int       = 0
    var totalDrinks: Int       = 0
    var avgDrinksPerNight: Double = 0
    var avgMinutesPerDrink: Double = 0
    var totalCalories: Double  = 0
    var totalAlcoholG: Double  = 0
    var favoriteDrink: String? = nil
    var busiestDay: String?    = nil
    var recordNight: (name: String, date: Date, total: Int)? = nil
    var weeklyStreak: Int      = 0
    var weekendStreak: Int     = 0
    var insights: [String]     = []
}

struct MonthlyStats {
    var totalEvents: Int       = 0
    var totalDrinks: Int       = 0
    var avgDrinksPerNight: Double = 0
    var totalCalories: Double  = 0
    var totalAlcoholG: Double  = 0
    var favoriteDrink: String? = nil
    var recordNight: (name: String, date: Date, total: Int)? = nil
    var quietestNight: (name: String, date: Date, total: Int)? = nil
    var drinksByType: [(name: String, count: Int)] = []
    var drinksByWeek: [(week: String, count: Int)] = []
}

struct AnalyticsEngine {

    static func allTime(events: [NightEvent], entries: [DrinkEntry], drinkTypes: [DrinkType]) -> AllTimeStats {
        let finished = events.filter { $0.endTime != nil }
        guard !finished.isEmpty else { return AllTimeStats() }

        let eventIds = Set(finished.map(\.id))
        let relevant = entries.filter { eventIds.contains($0.eventId) }

        var stats = AllTimeStats()
        stats.totalEvents = finished.count
        stats.totalDrinks = relevant.reduce(0) { $0 + $1.quantity }
        stats.avgDrinksPerNight = finished.isEmpty ? 0 : Double(stats.totalDrinks) / Double(finished.count)
        stats.totalAlcoholG = relevant.reduce(0.0) { sum, e in
            let dt = drinkTypes.first { $0.id == e.drinkTypeId }
            let vol = e.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = e.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + BACCalculator.calculateAlcohol(volumeMl: vol, abv: abv, quantity: e.quantity)
        }
        stats.totalCalories = relevant.reduce(0.0) { sum, e in
            let dt = drinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }
        stats.favoriteDrink = favoriteDrink(entries: relevant, drinkTypes: drinkTypes)
        stats.busiestDay = busiestDay(events: finished, entries: relevant)
        stats.avgMinutesPerDrink = avgMinutesPerDrink(events: finished, entries: relevant)
        stats.recordNight = recordNight(events: finished, entries: relevant)
        stats.weeklyStreak = weeklyStreak(events: finished)
        stats.weekendStreak = weekendStreak(events: finished)
        stats.insights = generateInsights(stats: stats)
        return stats
    }

    static func monthly(year: Int, month: Int, events: [NightEvent], entries: [DrinkEntry], drinkTypes: [DrinkType]) -> MonthlyStats {
        let cal = Calendar.current
        let finished = events.filter { event in
            guard let _ = event.endTime else { return false }
            let comps = cal.dateComponents([.year, .month], from: event.startTime)
            return comps.year == year && comps.month == month
        }
        guard !finished.isEmpty else { return MonthlyStats() }

        let eventIds = Set(finished.map(\.id))
        let relevant = entries.filter { eventIds.contains($0.eventId) }

        var stats = MonthlyStats()
        stats.totalEvents = finished.count
        stats.totalDrinks = relevant.reduce(0) { $0 + $1.quantity }
        stats.avgDrinksPerNight = Double(stats.totalDrinks) / Double(finished.count)
        stats.totalAlcoholG = relevant.reduce(0.0) { sum, e in
            let dt = drinkTypes.first { $0.id == e.drinkTypeId }
            let vol = e.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = e.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + BACCalculator.calculateAlcohol(volumeMl: vol, abv: abv, quantity: e.quantity)
        }
        stats.totalCalories = relevant.reduce(0.0) { sum, e in
            let dt = drinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }
        stats.favoriteDrink = favoriteDrink(entries: relevant, drinkTypes: drinkTypes)
        stats.recordNight = recordNight(events: finished, entries: relevant)
        stats.quietestNight = quietestNight(events: finished, entries: relevant)
        stats.drinksByType = drinksByType(entries: relevant, drinkTypes: drinkTypes)
        stats.drinksByWeek = drinksByWeek(entries: relevant)
        return stats
    }

    static func period(
        from: Date,
        to: Date,
        label: String,
        events: [NightEvent],
        entries: [DrinkEntry],
        drinkTypes: [DrinkType]
    ) -> PeriodStats {
        let finished = events.filter { $0.endTime != nil && $0.startTime >= from && $0.startTime < to }
        let eventIds = Set(finished.map(\.id))
        let relevant = entries.filter { eventIds.contains($0.eventId) }

        var stats = PeriodStats(label: label, from: from, to: to)
        stats.totalEvents = finished.count
        stats.totalDrinks = relevant.reduce(0) { $0 + $1.quantity }
        stats.avgDrinksPerNight = finished.isEmpty ? 0 : Double(stats.totalDrinks) / Double(finished.count)
        stats.totalAlcoholG = relevant.reduce(0.0) { sum, e in
            let dt = drinkTypes.first { $0.id == e.drinkTypeId }
            let vol = e.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = e.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + BACCalculator.calculateAlcohol(volumeMl: vol, abv: abv, quantity: e.quantity)
        }
        stats.totalCalories = relevant.reduce(0.0) { sum, e in
            let dt = drinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }
        stats.drinksByType = drinksByType(entries: relevant, drinkTypes: drinkTypes)

        let dayMap: [(String, Int)] = [
            ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5),
            ("Fri", 6), ("Sat", 7), ("Sun", 1)
        ]
        for (dayLabel, weekday) in dayMap {
            let dayEvents = finished.filter {
                Calendar.current.component(.weekday, from: $0.startTime) == weekday
            }
            let total = dayEvents.reduce(0) { count, event in
                count + relevant.filter { $0.eventId == event.id }.reduce(0) { $0 + $1.quantity }
            }
            stats.dayOfWeekAvg[dayLabel] = dayEvents.isEmpty ? 0 : Double(total) / Double(dayEvents.count)
        }
        return stats
    }

    // MARK: - Helpers

    private static func favoriteDrink(entries: [DrinkEntry], drinkTypes: [DrinkType]) -> String? {
        var counts: [String: Int] = [:]
        for e in entries { counts[e.drinkTypeId, default: 0] += e.quantity }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        return drinkTypes.first { $0.id == top.key }?.name
    }

    private static func busiestDay(events: [NightEvent], entries: [DrinkEntry]) -> String? {
        let days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        var counts = [Int: Int]()
        for event in events {
            let day = Calendar.current.component(.weekday, from: event.startTime) - 1
            let eventEntries = entries.filter { $0.eventId == event.id }
            counts[day, default: 0] += eventEntries.reduce(0) { $0 + $1.quantity }
        }
        return counts.max(by: { $0.value < $1.value }).map { days[$0.key] }
    }

    private static func avgMinutesPerDrink(events: [NightEvent], entries: [DrinkEntry]) -> Double {
        var totalMinutes = 0.0
        var count = 0
        for event in events {
            guard let end = event.endTime else { continue }
            let eventEntries = entries.filter { $0.eventId == event.id }
            let total = eventEntries.reduce(0) { $0 + $1.quantity }
            guard total > 0 else { continue }
            let duration = end.timeIntervalSince(event.startTime) / 60
            totalMinutes += duration / Double(total)
            count += 1
        }
        return count > 0 ? totalMinutes / Double(count) : 0
    }

    private static func recordNight(events: [NightEvent], entries: [DrinkEntry]) -> (name: String, date: Date, total: Int)? {
        var best: (event: NightEvent, total: Int)?
        for event in events {
            let total = entries.filter { $0.eventId == event.id }.reduce(0) { $0 + $1.quantity }
            if best == nil || total > best!.total { best = (event, total) }
        }
        guard let b = best else { return nil }
        return (b.event.displayName, b.event.startTime, b.total)
    }

    private static func quietestNight(events: [NightEvent], entries: [DrinkEntry]) -> (name: String, date: Date, total: Int)? {
        var best: (event: NightEvent, total: Int)?
        for event in events {
            let total = entries.filter { $0.eventId == event.id }.reduce(0) { $0 + $1.quantity }
            if best == nil || total < best!.total { best = (event, total) }
        }
        guard let b = best else { return nil }
        return (b.event.displayName, b.event.startTime, b.total)
    }

    private static func drinksByType(entries: [DrinkEntry], drinkTypes: [DrinkType]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for e in entries { counts[e.drinkTypeId, default: 0] += e.quantity }
        return counts
            .compactMap { id, count in drinkTypes.first { $0.id == id }.map { ($0.name, count) } }
            .sorted { $0.count > $1.count }
    }

    private static func drinksByWeek(entries: [DrinkEntry]) -> [(week: String, count: Int)] {
        var counts: [String: Int] = [:]
        let cal = Calendar.current
        for e in entries {
            let week = cal.component(.weekOfYear, from: e.timestamp)
            let key = "Week \(week)"
            counts[key, default: 0] += e.quantity
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.week < $1.week }
    }

    private static func isoWeek(_ date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return "\(year)-W\(String(format: "%02d", week))"
    }

    static func weeklyStreak(events: [NightEvent]) -> Int {
        let weeks = Set(events.map { isoWeek($0.startTime) }).sorted(by: >)
        guard !weeks.isEmpty else { return 0 }
        var streak = 1
        let cal = Calendar(identifier: .iso8601)
        for i in 1..<weeks.count {
            guard let prev = isoWeekDate(weeks[i-1], cal: cal),
                  let curr = isoWeekDate(weeks[i], cal: cal) else { break }
            let diff = cal.dateComponents([.weekOfYear], from: curr, to: prev).weekOfYear ?? 0
            if diff == 1 { streak += 1 } else { break }
        }
        return streak
    }

    static func weekendStreak(events: [NightEvent]) -> Int {
        let cal = Calendar.current
        let weekendEvents = events.filter {
            let wd = cal.component(.weekday, from: $0.startTime)
            return wd == 1 || wd == 6 || wd == 7
        }
        return weeklyStreak(events: weekendEvents)
    }

    private static func isoWeekDate(_ isoWeek: String, cal: Calendar) -> Date? {
        let parts = isoWeek.split(separator: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = 2
        return cal.date(from: comps)
    }

    private static func generateInsights(stats: AllTimeStats) -> [String] {
        var insights: [String] = []
        if stats.totalEvents > 0 {
            insights.append("You've tracked \(stats.totalEvents) night\(stats.totalEvents > 1 ? "s" : "") so far.")
        }
        if let fav = stats.favoriteDrink {
            insights.append("\(fav) is your go-to drink.")
        }
        if let day = stats.busiestDay {
            insights.append("\(day) is your most active night.")
        }
        if stats.weeklyStreak > 1 {
            insights.append("\(stats.weeklyStreak)-week streak of tracking!")
        }
        return insights
    }
}
