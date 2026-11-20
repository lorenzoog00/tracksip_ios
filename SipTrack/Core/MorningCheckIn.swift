import Foundation

/// Pure rules for the morning check-in: when the morning is, who gets the
/// notification, which night the Home card is for, how tiles toggle, and the
/// `morning` payload the server's `validateMorning` accepts.
enum MorningCheckIn {
    /// Notification category with the four quick answers.
    static let categoryId = "siptrack.morning"

    /// Notification action ids to the tile each one pre-selects.
    static let actionIds: [String: Symptom] = [
        "morning.headache": .headache,
        "morning.nausea": .nausea,
        "morning.wrecked": .wrecked,
        "morning.fine": .fine,
    ]

    /// Nights under this many standard drinks are light: no notification.
    static let lightNightStandardDrinks = 3.0

    /// The morning time comes this long after the night ends...
    static let hoursAfterEnd = 7
    /// ...but never before this local hour on that calendar day.
    static let earliestHour = 8

    // MARK: - Timing

    /// Night end + 7 elapsed hours, but not before 08:00 local on the calendar
    /// day that lands on. An end at 23:00 gives 06:00, which becomes 08:00.
    static func morningTime(nightEnd: Date, calendar: Calendar = .current) -> Date {
        let earliest = nightEnd.addingTimeInterval(TimeInterval(hoursAfterEnd * 3600))
        var parts = calendar.dateComponents([.year, .month, .day], from: earliest)
        parts.hour = earliestHour
        parts.minute = 0
        parts.second = 0
        guard let firstAllowed = calendar.date(from: parts) else { return earliest }
        return max(earliest, firstAllowed)
    }

    // MARK: - Eligibility

    /// Whether to schedule the morning notification: only when a plan can
    /// really be built (signed in, AI reports on, Pro or free plans left) and
    /// the night wasn't light.
    static func shouldNotify(standardDrinks: Double, signedIn: Bool, aiEnabled: Bool,
                             isPro: Bool, freePlansLeft: Int) -> Bool {
        guard standardDrinks.isFinite, standardDrinks >= lightNightStandardDrinks,
              signedIn, aiEnabled else { return false }
        return isPro || freePlansLeft > 0
    }

    /// The night the Home check-in card is for, or nil.
    ///
    /// Only the most recently started night counts: once the next night starts
    /// (active or ended), the previous night's card is gone. The night must
    /// have ended, have drinks, and `now` must be at or after its morning time.
    ///
    /// - Parameter plannedIds: event ids that must never get a check-in.
    ///   Callers fold in every night that already has a morning plan AND every
    ///   night that has an old night report (`event.aiReport != nil`) or an old
    ///   recovery brief (`NightRecovery`), so old nights keep their old cards.
    ///   (`aiReport` is also checked here directly, as a backstop.)
    static func checkInEventId(events: [NightEvent], standardDrinks: (NightEvent) -> Double,
                               plannedIds: Set<String>, now: Date,
                               calendar: Calendar = .current) -> String? {
        guard let latest = events.max(by: { $0.startTime < $1.startTime }),
              let end = latest.endTime,
              latest.aiReport == nil,
              !plannedIds.contains(latest.id),
              now >= morningTime(nightEnd: end, calendar: calendar) else { return nil }
        let drinks = standardDrinks(latest)
        guard drinks.isFinite, drinks > 0 else { return nil }
        return latest.id
    }

    // MARK: - Tiles and notification actions

    /// Tapping a tile: a selected tile deselects; `fine` clears the others;
    /// any other symptom clears `fine`.
    static func toggle(_ s: Symptom, in selected: Set<Symptom>) -> Set<Symptom> {
        if selected.contains(s) { return selected.subtracting([s]) }
        if s == .fine { return [.fine] }
        var next = selected
        next.remove(.fine)
        next.insert(s)
        return next
    }

    /// The tile a notification action pre-selects; nil for the default tap
    /// (`UNNotificationDefaultActionIdentifier`) or anything else.
    static func symptom(forAction id: String) -> Symptom? {
        actionIds[id]
    }

    // MARK: - Payload

    /// A country code `validateMorning` accepts: exactly two uppercase ASCII
    /// letters. The profile's code wins, then the device region. A region like
    /// "419" (a UN M.49 area) is not a country, so nothing is sent then.
    static func country(profileCode: String?, region: String?) -> String? {
        for candidate in [profileCode, region] {
            guard let code = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  code.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil else { continue }
            return code
        }
        return nil
    }

    /// The `morning` request payload for one night.
    ///
    /// `symptoms` must not be empty (the check-in button is disabled until a
    /// tile is picked). If `fine` arrives alongside others it is dropped,
    /// because the server only accepts `fine` alone. `country` is omitted
    /// when neither the profile nor the device region gives a valid code.
    static func payload(event: NightEvent, entries: [DrinkEntry], waters: [WaterEntry], foods: [FoodEntry],
                        drinkTypes: [DrinkType], profile: UserProfile, symptoms: Set<Symptom>, now: Date,
                        calendar: Calendar = .current,
                        region: String? = Locale.current.region?.identifier) -> [String: Any] {
        let nightEntries = entries.filter { $0.eventId == event.id }
        let nightWaters = waters.filter { $0.eventId == event.id }
        let nightFoods = foods.filter { $0.eventId == event.id }
        let end = event.endTime ?? now
        let stomach = event.stomachState ?? .empty

        let picked = symptoms.count > 1 ? symptoms.subtracting([Symptom.fine]) : symptoms
        let names = Symptom.allCases.filter { picked.contains($0) }.map(\.rawValue)

        let dose = ReportAlcoholDose(entries: nightEntries, drinkTypes: drinkTypes)
        let timeline = BACCalculator.bacTimeline(
            entries: nightEntries, drinkTypes: drinkTypes, profile: profile, eventStart: event.startTime,
            stomachState: stomach, stomachStateTimestamp: event.stomachStateTimestamp, foodEntries: nightFoods
        )
        let peakBac = timeline.map(\.bac).max() ?? 0
        let bacNow = nightEntries.isEmpty ? 0 : BACCalculator.currentBAC(
            entries: nightEntries, waterEntries: nightWaters, drinkTypes: drinkTypes, profile: profile,
            eventStart: event.startTime, stomachState: stomach,
            stomachStateTimestamp: event.stomachStateTimestamp, foodEntries: nightFoods, asOf: now
        )

        var payload: [String: Any] = [
            "symptoms": names,
            "checkInHour": calendar.component(.hour, from: now),
            "weekday": calendar.component(.weekday, from: now),
            "endHour": calendar.component(.hour, from: end),
            "durationMinutes": Int(max(0, end.timeIntervalSince(event.startTime)) / 60),
            "peakBac": finite(peakBac),
            "estimatedBacNow": finite(bacNow),
            "waterMl": finite(nightWaters.reduce(0) { $0 + $1.volumeMl }),
            "foodEntryCount": nightFoods.count,
            "stomachState": stomach.rawValue,
            "userSex": profile.sex.rawValue,
        ]
        payload.merge(dose.fields(start: event.startTime, end: end)) { _, new in new }
        if let code = country(profileCode: profile.countryCode, region: region) {
            payload["country"] = code
        }
        return payload
    }

    /// The server rejects non-finite numbers; a broken estimate becomes 0.
    private static func finite(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
