import Foundation
import FirebaseFirestore

/// One drink as a friend sees it: name, icon and time only. Never volume, ABV or comment.
nonisolated struct SharedDrink: Equatable {
    var name: String
    var icon: String
    var at: Date
}

/// The slice of a night that is shared with friends. Built from the owner's data,
/// written to Firestore, and read back by friends.
nonisolated struct SharedNight: Equatable {
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

    @MainActor
    static func build(
        event: NightEvent,
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        points: [BACDataPoint]
    ) -> SharedNight {
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
        // Never before the start: the rules reject a last drink earlier than started_at.
        let lastDrinkAt = max(sortedEntries.last?.timestamp ?? event.startTime, event.startTime)

        var allDrinks: [SharedDrink] = []
        for entry in sortedEntries {
            let type = drinkTypes.first { $0.id == entry.drinkTypeId }
            let drink = SharedDrink(
                name: type?.name ?? "Drink",
                icon: type?.icon ?? "beer-outline",
                at: entry.timestamp
            )
            allDrinks.append(contentsOf: Array(repeating: drink, count: max(0, entry.quantity)))
        }
        let drinks = Array(allDrinks.suffix(maxDrinks))

        let sortedPoints = points.sorted { $0.date < $1.date }
        var samples: [Double] = []
        var sawPositive = false
        while samples.count < maxSamples {
            let t = event.startTime.addingTimeInterval(Double(samples.count) * sampleInterval)
            let value: Double
            if let last = sortedPoints.last, t <= last.date {
                value = max(0, BACCalculator.interpolatedBAC(at: t, sorted: sortedPoints))
            } else {
                value = 0
            }
            samples.append(value)
            if value > 0 { sawPositive = true }
            // Stop at the first zero after the last drink, but only once the curve has
            // risen (or is past its last point): a drink logged at the start begins at 0.
            let pastCurve = sortedPoints.last.map { t > $0.date } ?? true
            if value <= 0, t >= lastDrinkAt, sawPositive || pastCurve { break }
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

    /// Earliest time a friend's night may carry: 2020-01-01 in ms.
    static let earliestMs: Double = 1_577_836_800_000
    /// How far past `now` a time may sit (clock skew): two days in ms.
    static let futureSlackMs: Double = 172_800_000
    /// Highest BAC a sample may show; higher values are clamped.
    static let maxSampleBAC: Double = 1.0

    /// Friends' docs are untrusted: a modified client can write any number the rules
    /// let through. Rejects non-finite or out-of-window times (2020-01-01 ... now + 2 days)
    /// and non-finite samples; clamps samples to 0...1, and a last drink or end before
    /// the start (older builds can write a backdated last drink) to the start. Nothing
    /// built here can trap when converted to Int later.
    init?(firestore data: [String: Any], now: Date = Date()) {
        let latest = now.timeIntervalSince1970 * 1000 + SharedNight.futureSlackMs
        guard let started = SharedNight.time(data["started_at"], latest: latest),
              let rawLastDrink = SharedNight.time(data["last_drink_at"], latest: latest),
              let expires = data["expires_at"] as? Timestamp,
              let rawSamples = data["samples"] as? [Any],
              let rawDrinks = data["drinks"] as? [Any]
        else { return nil }

        let lastDrink = max(rawLastDrink, started)
        var ended: Double?
        if let rawEnded = data["ended_at"], !(rawEnded is NSNull) {
            guard let e = SharedNight.time(rawEnded, latest: latest) else { return nil }
            ended = max(e, started)
        }

        var samples: [Double] = []
        for raw in rawSamples {
            guard let v = SharedNight.number(raw), v.isFinite else { return nil }
            samples.append(min(max(v, 0), SharedNight.maxSampleBAC))
        }

        var drinks: [SharedDrink] = []
        for raw in rawDrinks {
            guard let dict = raw as? [String: Any],
                  let name = dict["name"] as? String,
                  let icon = dict["icon"] as? String,
                  let at = SharedNight.time(dict["at"], latest: latest)
            else { return nil }
            drinks.append(SharedDrink(name: name, icon: icon, at: SharedNight.date(ms: at)))
        }

        let expiresAt = expires.dateValue()
        guard expiresAt.timeIntervalSince1970.isFinite else { return nil }

        self.init(
            startedAt: SharedNight.date(ms: started),
            endedAt: ended.map { SharedNight.date(ms: $0) },
            lastDrinkAt: SharedNight.date(ms: lastDrink),
            expiresAt: expiresAt,
            samples: samples,
            drinks: drinks
        )
    }

    /// The start in ms: `started_at` in Firestore, the id of the night's ended copy
    /// (`shared_nights/{uid}/ended/{startedAtMs}`) and the second half of its `NightKey`.
    var startedAtMs: Int64 { SharedNight.ms(startedAt) }

    /// Never traps: a non-finite or out-of-range date gives 0.
    static func ms(_ date: Date) -> Int64 {
        let value = (date.timeIntervalSince1970 * 1000).rounded()
        guard value.isFinite, let ms = Int64(exactly: value) else { return 0 }
        return ms
    }

    /// A time in ms if it is finite and inside 2020-01-01 ... `latest`.
    private static func time(_ value: Any?, latest: Double) -> Double? {
        guard let v = number(value), v.isFinite, v >= earliestMs, v <= latest else { return nil }
        return v
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
