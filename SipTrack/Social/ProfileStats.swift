import Foundation

/// One finished night as the profile stats see it: when it started, whether it was
/// incognito, and counts. No name, notes, BAC or place.
nonisolated struct NightSummary: Equatable, Sendable {
    var start: Date
    var incognito: Bool
    /// Servings logged: each entry counts its quantity, as SharedNight counts drinks.
    var drinks: Int
    /// Glasses of water logged: one WaterEntry is one glass.
    var waters: Int
    /// One display name per serving. Drinks whose type no longer exists are left out.
    var drinkNames: [String]
}

extension NightSummary {
    /// The user's finished nights. A night still running is left out until it ends.
    /// Drinks are named the way SharedNight names them: by the first type with that id
    /// in `drinkTypes` (pass `AppState.allDrinkTypes`, presets plus custom types).
    @MainActor
    static func summaries(
        events: [NightEvent],
        entries: [DrinkEntry],
        waterEntries: [WaterEntry],
        drinkTypes: [DrinkType],
        userId: String
    ) -> [NightSummary] {
        var names: [String: String] = [:]
        for type in drinkTypes where names[type.id] == nil {
            names[type.id] = type.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let entriesByNight = Dictionary(grouping: entries) { $0.eventId }
        var watersByNight: [String: Int] = [:]
        for water in waterEntries { watersByNight[water.eventId, default: 0] += 1 }

        return events.compactMap { event -> NightSummary? in
            guard event.userId == userId, event.endTime != nil else { return nil }
            var drinks = 0
            var drinkNames: [String] = []
            for entry in entriesByNight[event.id] ?? [] {
                let servings = max(0, entry.quantity)
                drinks += servings
                if let name = names[entry.drinkTypeId], !name.isEmpty {
                    drinkNames.append(contentsOf: repeatElement(name, count: servings))
                }
            }
            return NightSummary(
                start: event.startTime,
                incognito: event.isIncognito,
                drinks: drinks,
                waters: watersByNight[event.id] ?? 0,
                drinkNames: drinkNames
            )
        }
    }
}

/// What friends see on the stats card, computed on the owner's phone and written to
/// `profile_stats/{uid}`. Safe stats only: no BAC, records, streaks or rankings.
nonisolated struct ProfileStats: Equatable, Sendable {
    /// The window for the averages and the favorite drink. `nights` is all time.
    static let window: TimeInterval = 90 * 86_400
    /// A foreground recomputes stats older than this: the window moves with the clock.
    static let refreshInterval: TimeInterval = 86_400
    /// Rules limits: `favorite_drink` ≤ 40 characters, `nights` 0…100 000, averages 0…100.
    static let maxFavoriteLength = 40
    static let maxNights = 100_000
    static let maxAverage: Double = 100

    var nights: Int
    /// Nil when no night counts in the window. Written as 0; the card shows "No stats
    /// yet" when `nights == 0`.
    var avgDrinks: Double?
    var avgWater: Double?
    var favoriteDrink: String?
    var memberSince: Date

    /// Incognito nights and nights with no drinks never count. `nights` counts the rest,
    /// all time. The averages are over the rest that started in the last 90 days
    /// (`start >= now - 90 days`), to one decimal, or nil when there are none. The
    /// favorite is the most logged name in that window, ties in alphabetical order,
    /// cut to 40 characters.
    nonisolated static func compute(nights: [NightSummary], memberSince: Date, now: Date) -> ProfileStats {
        let counted = nights.filter { !$0.incognito && $0.drinks > 0 }
        let windowStart = now.addingTimeInterval(-window)
        let recent = counted.filter { $0.start >= windowStart }

        var stats = ProfileStats(
            nights: counted.count, avgDrinks: nil, avgWater: nil,
            favoriteDrink: nil, memberSince: memberSince
        )
        // No night in the window: no average, and nothing to divide by.
        guard !recent.isEmpty else { return stats }
        let count = Double(recent.count)
        stats.avgDrinks = oneDecimal(Double(recent.reduce(0) { $0 + $1.drinks }) / count)
        stats.avgWater = oneDecimal(Double(recent.reduce(0) { $0 + max(0, $1.waters) }) / count)
        stats.favoriteDrink = favorite(in: recent.flatMap { $0.drinkNames })
        return stats
    }

    nonisolated static func oneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// The most frequent name; a tie goes to the name first in alphabetical order
    /// (case-insensitive, then exact so the result never depends on input order).
    nonisolated static func favorite(in names: [String]) -> String? {
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        let ranked = counts.min(by: { a, b in
            if a.value != b.value { return a.value > b.value }
            let order = a.key.compare(b.key, options: .caseInsensitive)
            if order != .orderedSame { return order == .orderedAscending }
            return a.key < b.key
        })
        guard let best = ranked else { return nil }
        let name = truncated(best.key)
        return name.isEmpty ? nil : name
    }

    /// At most 40 characters, cut on whole characters. Also at most 40 code points, so
    /// a name of long emoji sequences can't pass here and fail the rules' size check.
    nonisolated static func truncated(_ name: String) -> String {
        var result = String(name.prefix(maxFavoriteLength))
        while result.unicodeScalars.count > maxFavoriteLength { result.removeLast() }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Exactly the keys the rules allow. `nights`, `member_since` and `updated_at` are
    /// Int (the rules want ints; a Double is denied); the averages are written as 0 when
    /// nil; `favorite_drink` is left out when nil (never NSNull). Everything is clamped
    /// to the rules' ranges.
    nonisolated func firestoreData(updatedAt: Date) -> [String: Any] {
        var data: [String: Any] = [
            "nights": min(max(nights, 0), ProfileStats.maxNights),
            "avg_drinks": ProfileStats.bounded(avgDrinks),
            "avg_water": ProfileStats.bounded(avgWater),
            "member_since": ProfileStats.ms(memberSince),
            "updated_at": ProfileStats.ms(updatedAt)
        ]
        if let favoriteDrink { data["favorite_drink"] = favoriteDrink }
        return data
    }

    var firestoreData: [String: Any] { firestoreData(updatedAt: Date()) }

    private nonisolated static func bounded(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, 0), maxAverage)
    }

    /// Never traps: a non-finite or out-of-range date gives 0.
    private nonisolated static func ms(_ date: Date) -> Int {
        Int(exactly: (date.timeIntervalSince1970 * 1000).rounded()) ?? 0
    }
}

// In an extension so the memberwise init stays.
extension ProfileStats {
    /// A `profile_stats` doc read back: the inverse of `firestoreData` (which adds
    /// `updated_at`, ignored here). Numbers may come back as Int, Double or NSNumber.
    /// Nil without `nights` or `member_since`. An `avg_drinks` of 0 means no night in
    /// the window (a counted night has at least one drink), so both averages read back
    /// as nil, as `compute` left them. A missing or blank `favorite_drink` is nil.
    /// Values are kept to the same ranges as on the way out.
    nonisolated init?(firestore data: [String: Any]) {
        guard let nights = Self.number(data["nights"]),
              let since = Self.number(data["member_since"]) else { return nil }
        let drinks = Self.number(data["avg_drinks"]).map { min(max($0, 0), Self.maxAverage) }
        let water = Self.number(data["avg_water"]).map { min(max($0, 0), Self.maxAverage) }
        let inWindow = (drinks ?? 0) > 0
        let favorite = (data["favorite_drink"] as? String).map { Self.truncated($0) }
        self.init(
            nights: Int(min(max(nights, 0), Double(Self.maxNights)).rounded()),
            avgDrinks: inWindow ? drinks : nil,
            avgWater: inWindow ? water : nil,
            favoriteDrink: (favorite?.isEmpty ?? true) ? nil : favorite,
            memberSince: Date(timeIntervalSince1970: since / 1000)
        )
    }

    /// A finite number however Firestore hands it back.
    private nonisolated static func number(_ raw: Any?) -> Double? {
        guard let raw else { return nil }
        let value: Double
        switch raw {
        case let int as Int: value = Double(int)
        case let int as Int64: value = Double(int)
        case let double as Double: value = double
        case let boxed as NSNumber: value = boxed.doubleValue
        default: return nil
        }
        return value.isFinite ? value : nil
    }
}

enum ProfileStatsPublisher {
    /// Off never writes (the caller deletes the doc instead). Otherwise only a change is
    /// written: `ProfileStats` has no `updated_at`, so equal stats mean nothing changed.
    nonisolated static func shouldWrite(new: ProfileStats, last: ProfileStats?, enabled: Bool) -> Bool {
        guard enabled else { return false }
        return new != last
    }

    /// True when the stats were never computed this session, or a day or more ago.
    nonisolated static func isStale(checkedAt: Date?, now: Date) -> Bool {
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= ProfileStats.refreshInterval
    }
}

/// "Show my stats to friends", per account, on this phone. On unless turned off.
///
/// Kept here rather than in UserProfile: the profile doc's rules allow a fixed key list,
/// so it can't sync, and a local UserProfile field is reset by every sign-out, which
/// would quietly turn sharing back on. A plain sign-out keeps this; account deletion
/// clears it.
enum ProfileStatsSharing {
    static func isOn(uid: String) -> Bool {
        !UserDefaults.standard.bool(forKey: key(uid))
    }

    static func set(_ on: Bool, uid: String) {
        if on {
            UserDefaults.standard.removeObject(forKey: key(uid))
        } else {
            UserDefaults.standard.set(true, forKey: key(uid))
        }
    }

    static func clear(uid: String) {
        UserDefaults.standard.removeObject(forKey: key(uid))
    }

    private static func key(_ uid: String) -> String {
        "profileStatsHidden.\(uid)"
    }
}
