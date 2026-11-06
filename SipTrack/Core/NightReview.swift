import Foundation
import CoreGraphics

struct NightReview {
    struct Highlight: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let time: Date
        let relatedTime: Date?
    }

    struct Comparison {
        let count: Int
        let pace: Double
        let usualPace: Double
        let water: Double
        let usualWater: Double
    }

    let event: NightEvent
    let end: Date
    let entries: [DrinkEntry]
    let waters: [WaterEntry]
    let foods: [FoodEntry]
    let timeline: [BACDataPoint]
    let dose: [(time: Date, grams: Double)]
    let calories: Double
    let ceiling: StoryCeiling
    let comparison: Comparison?

    var drinkCount: Int { entries.reduce(0) { $0 + $1.quantity } }
    var alcoholGrams: Double { dose.reduce(0) { $0 + $1.grams } }
    var standardDrinks: Double { BACCalculator.standardDrinks(alcoholGrams: alcoholGrams) }
    var peak: BACDataPoint? { timeline.filter { $0.bac > 0 }.max { $0.bac < $1.bac } }
    var path: BACPath { BACPath(timeline: timeline, start: event.startTime, end: end) }

    init(event: NightEvent, entries: [DrinkEntry], waters: [WaterEntry], foods: [FoodEntry],
         drinkTypes: [DrinkType], profile: UserProfile, previousEvents: [NightEvent], now: Date = .now) {
        self.event = event
        let end = max(event.startTime, event.endTime ?? now)
        self.end = end
        let logged = entries.filter { $0.eventId == event.id && $0.timestamp <= end }.sorted { $0.timestamp < $1.timestamp }
        self.entries = logged
        let water = waters.filter { $0.eventId == event.id && $0.timestamp <= end }.sorted { $0.timestamp < $1.timestamp }
        self.waters = water
        let food = foods.filter { $0.eventId == event.id && $0.timestamp <= end }
        self.foods = food
        self.timeline = BACCalculator.bacTimeline(
            entries: logged, drinkTypes: drinkTypes, profile: profile, eventStart: event.startTime,
            stomachState: event.stomachState ?? .empty, stomachStateTimestamp: event.stomachStateTimestamp, foodEntries: food
        )
        let doses = logged.map { (time: $0.timestamp, grams: Self.grams($0, drinkTypes: drinkTypes)) }.filter { $0.grams > 0 }
        self.dose = doses
        self.calories = logged.reduce(0) { total, entry in
            guard let type = drinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { return total }
            return total + type.calories(volumeMl: entry.volumeOverrideMl ?? type.defaultVolumeMl, quantity: entry.quantity)
        }
        self.ceiling = StoryCeiling(event: event, profile: profile)
        self.comparison = Self.compare(event: event, end: end, logged: logged, water: water,
                                       entries: entries, waters: waters, drinkTypes: drinkTypes, previousEvents: previousEvents)
    }

    func bac(at time: Date) -> Double {
        guard let first = timeline.first, time >= first.date else { return 0 }
        return BACCalculator.interpolatedBAC(at: time, sorted: timeline)
    }

    func strongestWindow(seconds: TimeInterval) -> (start: Date, end: Date, grams: Double)? {
        guard dose.count >= 2, seconds > 0 else { return nil }
        var right = 0
        var total = 0.0
        var best: (Date, Date, Double)?
        for left in dose.indices {
            let start = dose[left].time
            let windowEnd = start.addingTimeInterval(seconds)
            while right < dose.count, dose[right].time < windowEnd {
                total += dose[right].grams
                right += 1
            }
            if total > (best?.2 ?? 0) {
                best = (start, min(end, windowEnd), total)
            }
            total -= dose[left].grams
        }
        return best
    }

    var highlights: [Highlight] {
        var result: [Highlight] = []
        if let window = strongestWindow(seconds: 3600), alcoholGrams > 0 {
            let percent = min(100, Int((window.grams / alcoholGrams * 100).rounded()))
            result.append(Highlight(id: "pace", icon: "clock", title: "Most concentrated stretch",
                detail: "\(Self.time(window.start)) to \(Self.time(window.end)) · \(percent)% of the alcohol logged",
                time: window.start, relatedTime: window.end))
        }
        if let peak, let last = dose.last?.time {
            let minutes = Int((peak.date.timeIntervalSince(last) / 60).rounded())
            let note = minutes > 0 ? " · \(minutes) min after the last drink logged" : ""
            let title = peak.date > end ? "Projected peak after close" : "Estimated peak"
            result.append(Highlight(id: "peak", icon: "waveform.path.ecg", title: title,
                detail: String(format: "%.3f%% at %@", peak.bac, Self.time(peak.date)) + note,
                time: peak.date, relatedTime: last == peak.date ? nil : last))
        }
        if let first = dose.first?.time, let last = dose.last?.time, last > first {
            let boundaries = [first] + waters.map(\.timestamp).filter { $0 > first && $0 < last } + [last]
            if let gap = zip(boundaries, boundaries.dropFirst()).max(by: {
                $0.1.timeIntervalSince($0.0) < $1.1.timeIntervalSince($1.0)
            }), gap.1.timeIntervalSince(gap.0) >= 1800 {
                let minutes = Int(gap.1.timeIntervalSince(gap.0) / 60)
                result.append(Highlight(id: "water", icon: "drop", title: "Longest gap without logged water",
                    detail: "\(Self.duration(minutes)) · \(Self.time(gap.0)) to \(Self.time(gap.1))",
                    time: gap.0, relatedTime: gap.1))
            }
        }
        return result
    }

    private static func grams(_ entry: DrinkEntry, drinkTypes: [DrinkType]) -> Double {
        let type = drinkTypes.first { $0.id == entry.drinkTypeId }
        return BACCalculator.calculateAlcohol(volumeMl: entry.volumeOverrideMl ?? type?.defaultVolumeMl ?? 0,
                                              abv: entry.abvOverride ?? type?.defaultAbv ?? 0, quantity: entry.quantity)
    }

    private static func compare(event: NightEvent, end: Date, logged: [DrinkEntry], water: [WaterEntry],
                                entries: [DrinkEntry], waters: [WaterEntry], drinkTypes: [DrinkType],
                                previousEvents: [NightEvent]) -> Comparison? {
        func metrics(_ drinks: [DrinkEntry], _ water: [WaterEntry], hours: Double) -> (pace: Double, water: Double)? {
            let count = drinks.reduce(0) { $0 + $1.quantity }
            let grams = drinks.reduce(0) { $0 + Self.grams($1, drinkTypes: drinkTypes) }
            guard count > 0, grams > 0, hours >= 1.0 / 60 else { return nil }
            return (BACCalculator.standardDrinks(alcoholGrams: grams) / hours,
                    water.reduce(0) { $0 + $1.volumeMl } / 250 / Double(count))
        }
        guard let current = metrics(logged, water, hours: end.timeIntervalSince(event.startTime) / 3600) else { return nil }
        let grouped = Dictionary(grouping: entries, by: \.eventId)
        let waterByEvent = Dictionary(grouping: waters, by: \.eventId)
        let recent = previousEvents.filter {
            $0.id != event.id && $0.userId == event.userId && ($0.endTime ?? .distantFuture) <= event.startTime
        }.sorted { ($0.endTime ?? .distantPast) > ($1.endTime ?? .distantPast) }
        let prior = Array(recent.lazy.compactMap { night in
            guard let end = night.endTime else { return nil as (pace: Double, water: Double)? }
            return metrics((grouped[night.id] ?? []).filter { $0.timestamp <= end },
                           (waterByEvent[night.id] ?? []).filter { $0.timestamp <= end },
                           hours: end.timeIntervalSince(night.startTime) / 3600)
        }.prefix(5))
        guard prior.count >= 3 else { return nil }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted()
            return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        }
        return Comparison(count: prior.count, pace: current.pace, usualPace: median(prior.map(\.pace)),
                          water: current.water, usualWater: median(prior.map(\.water)))
    }

    static func time(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes) min"
    }
}

enum ActivityEquivalence: CaseIterable {
    case running, cycling, swimming, walking

    var name: String {
        switch self {
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .walking: "Walking"
        }
    }

    var icon: String {
        switch self {
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .walking: "figure.walk"
        }
    }

    private var caloriesPerMinute: Double {
        switch self {
        case .running: 10
        case .cycling: 8
        case .swimming: 7
        case .walking: 4.5
        }
    }

    func duration(calories: Double) -> String {
        let minutes = Int(calories / caloriesPerMinute)
        return minutes > 0 ? NightReview.duration(minutes) : "<1 min"
    }
}

struct StoryCeiling {
    let value: Double
    let isPersonal: Bool
    var line: Double? { value > 0.005 ? value : nil }
    var name: String { isPersonal ? "Personal ceiling" : "Driving limit" }

    init(event: NightEvent, profile: UserProfile) {
        isPersonal = event.targetBAC != nil
        value = event.targetBAC ?? event.bacLimit ?? profile.resolvedBACLimit
    }
}

struct BACPath {
    let samples: [BACDataPoint]
    let start: Date
    let end: Date

    init(timeline: [BACDataPoint], start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
        let sorted = timeline.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { samples = []; return }
        func value(at date: Date) -> Double {
            guard let first = sorted.first, date >= first.date else { return 0 }
            return BACCalculator.interpolatedBAC(at: date, sorted: sorted)
        }
        samples = [BACDataPoint(date: start, bac: value(at: start))]
            + sorted.filter { $0.date > start && $0.date < end }
            + (end > start ? [BACDataPoint(date: end, bac: value(at: end))] : [])
    }

    func cgPath(in size: CGSize, yMax: Double) -> CGPath {
        let path = CGMutablePath()
        for (index, sample) in samples.enumerated() {
            let point = point(at: sample.date, bac: sample.bac, in: size, yMax: yMax)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    func yMax(ceiling: Double?) -> Double {
        max(0.01, ceiling ?? 0, samples.map(\.bac).max() ?? 0) * 1.15
    }

    func point(at date: Date, bac: Double, in size: CGSize, yMax: Double) -> CGPoint {
        let fraction = min(1, max(0, date.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))))
        let relativeBAC = min(1, max(0, bac / max(0.001, yMax)))
        return CGPoint(x: size.width * CGFloat(fraction), y: size.height * CGFloat(1 - relativeBAC))
    }

    func above(_ threshold: Double) -> (seconds: TimeInterval, firstCrossing: Date?, lastReturn: Date?) {
        var seconds: TimeInterval = 0
        var firstCrossing = samples.first.flatMap { $0.bac > threshold ? $0.date : nil }
        var lastReturn: Date?
        for (a, b) in zip(samples, samples.dropFirst()) {
            let elapsed = b.date.timeIntervalSince(a.date)
            if a.bac > threshold && b.bac > threshold {
                seconds += elapsed
            } else if (a.bac > threshold) != (b.bac > threshold) {
                let fraction = (threshold - a.bac) / (b.bac - a.bac)
                let crossing = a.date.addingTimeInterval(elapsed * fraction)
                if b.bac > threshold {
                    seconds += elapsed * (1 - fraction)
                    if firstCrossing == nil { firstCrossing = crossing }
                    lastReturn = nil
                } else {
                    seconds += elapsed * fraction
                    lastReturn = crossing
                }
            }
        }
        return (seconds, firstCrossing, lastReturn)
    }
}

extension AppState {
    func nightReview(for event: NightEvent) -> NightReview {
        NightReview(event: event, entries: entries, waters: waterEntries, foods: foodEntries,
                    drinkTypes: allDrinkTypes, profile: userProfile, previousEvents: visibleEvents)
    }
}
