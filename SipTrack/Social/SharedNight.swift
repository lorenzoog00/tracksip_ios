import Foundation
import FirebaseFirestore

/// One drink as a friend sees it: name, icon and time only. Never volume, ABV or comment.
struct SharedDrink: Equatable {
    var name: String
    var icon: String
    var at: Date
}

/// The slice of a night that is shared with friends. Built from the owner's data,
/// written to Firestore, and read back by friends.
struct SharedNight: Equatable {
    static let sampleInterval: TimeInterval = 300
    static let maxSamples = 300
    static let maxDrinks = 100
    static let lifetime: TimeInterval = 86400

    var startedAt: Date
    var endedAt: Date?
    var lastDrinkAt: Date
    var expiresAt: Date
    /// BAC every 300 s from `startedAt`.
    var samples: [Double]
    var drinks: [SharedDrink]

    init(startedAt: Date, endedAt: Date?, lastDrinkAt: Date, expiresAt: Date,
         samples: [Double], drinks: [SharedDrink]) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lastDrinkAt = lastDrinkAt
        self.expiresAt = expiresAt
        self.samples = samples
        self.drinks = drinks
    }

    // MARK: - Build

    static func build(
        event: NightEvent,
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        points: [BACDataPoint]
    ) -> SharedNight {
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
        let lastDrinkAt = sortedEntries.last?.timestamp ?? event.startTime

        var allDrinks: [SharedDrink] = []
        for entry in sortedEntries {
            let type = drinkTypes.first { $0.id == entry.drinkTypeId }
            let drink = SharedDrink(
                name: type?.name ?? "Drink",
                icon: type?.icon ?? "beer",
                at: entry.timestamp
            )
            allDrinks.append(contentsOf: Array(repeating: drink, count: max(0, entry.quantity)))
        }
        let drinks = Array(allDrinks.suffix(maxDrinks))

        let sortedPoints = points.sorted { $0.date < $1.date }
        var samples: [Double] = []
        while samples.count < maxSamples {
            let t = event.startTime.addingTimeInterval(Double(samples.count) * sampleInterval)
            let value: Double
            if let last = sortedPoints.last, t <= last.date {
                value = max(0, BACCalculator.interpolatedBAC(at: t, sorted: sortedPoints))
            } else {
                value = 0
            }
            samples.append(value)
            if value <= 0, t >= lastDrinkAt { break }
        }

        let expiresAt = (event.endTime ?? lastDrinkAt).addingTimeInterval(lifetime)
        return SharedNight(
            startedAt: event.startTime,
            endedAt: event.endTime,
            lastDrinkAt: lastDrinkAt,
            expiresAt: expiresAt,
            samples: samples,
            drinks: drinks
        )
    }

    // MARK: - Reading

    /// Linear interpolation of `samples`; 0 before the start or after the last sample.
    func bac(at date: Date) -> Double {
        guard let lastSample = samples.last else { return 0 }
        let offset = date.timeIntervalSince(startedAt)
        guard offset >= 0 else { return 0 }
        let position = offset / SharedNight.sampleInterval
        let lastIndex = samples.count - 1
        if position > Double(lastIndex) { return 0 }
        let lower = Int(position.rounded(.down))
        if lower >= lastIndex { return lastSample }
        let fraction = position - Double(lower)
        return samples[lower] + (samples[lower + 1] - samples[lower]) * fraction
    }

    var peakBAC: Double { samples.max() ?? 0 }

    var drinkCount: Int { drinks.count }

    func isLive(now: Date) -> Bool {
        endedAt == nil && expiresAt > now
    }

    // MARK: - Firestore

    /// Privacy: drinks carry only name, icon and time. Firestore rules cannot inspect
    /// list elements, so the client is the only guard against leaking more.
    func firestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "started_at": SharedNight.ms(startedAt),
            "last_drink_at": SharedNight.ms(lastDrinkAt),
            "expires_at": Timestamp(date: expiresAt),
            "samples": samples,
            "drinks": drinks.map { drink -> [String: Any] in
                ["name": drink.name, "icon": drink.icon, "at": SharedNight.ms(drink.at)]
            }
        ]
        if let endedAt { data["ended_at"] = SharedNight.ms(endedAt) }
        return data
    }

    init?(firestore data: [String: Any]) {
        guard let started = SharedNight.number(data["started_at"]),
              let lastDrink = SharedNight.number(data["last_drink_at"]),
              let expires = data["expires_at"] as? Timestamp,
              let rawSamples = data["samples"] as? [Any],
              let rawDrinks = data["drinks"] as? [Any]
        else { return nil }

        let samples = rawSamples.compactMap { SharedNight.number($0) }
        guard samples.count == rawSamples.count else { return nil }

        var drinks: [SharedDrink] = []
        for raw in rawDrinks {
            guard let dict = raw as? [String: Any],
                  let name = dict["name"] as? String,
                  let icon = dict["icon"] as? String,
                  let at = SharedNight.number(dict["at"])
            else { return nil }
            drinks.append(SharedDrink(name: name, icon: icon, at: SharedNight.date(ms: at)))
        }

        self.init(
            startedAt: SharedNight.date(ms: started),
            endedAt: SharedNight.number(data["ended_at"]).map { SharedNight.date(ms: $0) },
            lastDrinkAt: SharedNight.date(ms: lastDrink),
            expiresAt: expires.dateValue(),
            samples: samples,
            drinks: drinks
        )
    }

    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func date(ms: Double) -> Date {
        Date(timeIntervalSince1970: ms / 1000)
    }

    /// Firestore hands numbers back as Int, Int64 or Double depending on the value.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as Int64: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return nil
        }
    }
}
