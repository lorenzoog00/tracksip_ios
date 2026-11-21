import Foundation
import UserNotifications

/// What one morning-plan request came to.
enum MorningOutcome: Equatable {
    /// The plan exists: store it.
    case ready(MorningRecord)
    /// Another request for this night is still being built: poll the doc.
    case poll
    /// A free user is out of plans this month: show the blurred sample.
    case locked
    /// Nothing in the photo library fits this check-in, so the server refused
    /// it (for free): a friendly "no plan for this one", not an error.
    case unavailable
    /// Anything else went wrong: offer a retry.
    case failed
}

/// Pure rules for the morning check-in: when the morning is, who gets the
/// notification, which night the Home card is for, how tiles toggle, the
/// `morning` payload the server's `validateMorning` accepts, and how the
/// server's answer and the notification's response are read.
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

    /// The order the quick answers appear in on press and hold.
    static let actionOrder = ["morning.headache", "morning.nausea", "morning.wrecked", "morning.fine"]

    /// Every morning notification's identifier starts with this; the night's
    /// event id follows.
    static let notificationPrefix = "siptrack.morning-"
    static let notificationTitle = "Rough night? 🥴"
    static let notificationBody = "Tell us how you feel and get your recovery plan."

    /// Nights under this many standard drinks are light: no notification.
    static let lightNightStandardDrinks = 3.0

    /// The morning time comes this long after the night ends...
    static let hoursAfterEnd = 7
    /// ...but never before this local hour on that calendar day.
    static let earliestHour = 8

    /// The check-in card and the notification only apply this long after the
    /// night ends. A "Morning after" card days later is nonsense.
    static let checkInWindow: TimeInterval = 48 * 3600

    /// Free plans a month, as `FREE_LIMITS.morning` on the server.
    static let freeMonthlyPlans = 3

    /// The callable's answer to a `morning` request.
    typealias Response = (record: MorningRecord?, pending: Bool, remaining: Int?)

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

    /// Whether `now` is still within 48 h of the night's end.
    static func isWithinCheckInWindow(nightEnd: Date, now: Date) -> Bool {
        now.timeIntervalSince(nightEnd) < checkInWindow
    }

    /// When to fire the morning notification for a night that ended at
    /// `nightEnd`: its morning time, or nil when that has already passed or
    /// falls outside the check-in window.
    static func notificationDate(nightEnd: Date, now: Date, calendar: Calendar = .current) -> Date? {
        let fire = morningTime(nightEnd: nightEnd, calendar: calendar)
        guard fire > now, isWithinCheckInWindow(nightEnd: nightEnd, now: fire) else { return nil }
        return fire
    }

    // MARK: - Eligibility

    /// Whether to schedule the morning notification: only when a plan can
    /// really be built (signed in, AI reports on, Pro or free plans left) and
    /// the night wasn't light.
    ///
    /// A night with servings the app couldn't measure (`missingServings > 0`)
    /// counts as at least 3 standard drinks, as the server treats such a dose
    /// as heavy.
    static func shouldNotify(standardDrinks: Double, missingServings: Int = 0, signedIn: Bool,
                             aiEnabled: Bool, isPro: Bool, freePlansLeft: Int) -> Bool {
        let heavyEnough = missingServings > 0
            || (standardDrinks.isFinite && standardDrinks >= lightNightStandardDrinks)
        guard heavyEnough, signedIn, aiEnabled else { return false }
        return isPro || freePlansLeft > 0
    }

    /// The night the Home check-in card is for, or nil.
    ///
    /// Only the most recently started night counts: once the next night starts
    /// (active or ended), the previous night's card is gone. The night must
    /// have ended, have drinks (logged servings, measurable or not), and `now`
    /// must be at or after its morning time and within 48 h of its end.
    ///
    /// - Parameter plannedIds: event ids that must never get a check-in.
    ///   Callers fold in every night that already has a morning plan AND every
    ///   night that has an old night report (`event.aiReport != nil`) or an old
    ///   recovery brief (`NightRecovery`), so old nights keep their old cards.
    ///   (`aiReport` is also checked here directly, as a backstop.)
    static func checkInEventId(events: [NightEvent], loggedServings: (NightEvent) -> Int,
                               plannedIds: Set<String>, now: Date,
                               calendar: Calendar = .current) -> String? {
        guard let latest = events.max(by: { $0.startTime < $1.startTime }),
              let end = latest.endTime,
              latest.aiReport == nil,
              !plannedIds.contains(latest.id),
              now >= morningTime(nightEnd: end, calendar: calendar),
              isWithinCheckInWindow(nightEnd: end, now: now),
              loggedServings(latest) > 0 else { return nil }
        return latest.id
    }

    // MARK: - Free plans

    /// The quota month as the server counts it: UTC `yyyy-MM`.
    static func monthKey(for date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = utc.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Free plans left this month from the stored `[month: left]` allowance;
    /// a month with nothing stored starts at the full allowance.
    static func freePlansLeft(allowance: [String: Int], now: Date) -> Int {
        max(0, allowance[monthKey(for: now)] ?? freeMonthlyPlans)
    }

    /// The allowance to store after setting this month's count to `left`.
    /// Earlier months are dropped.
    static func allowance(left: Int, now: Date) -> [String: Int] {
        [monthKey(for: now): max(0, left)]
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

    // MARK: - Notification

    /// Opens the check-in for a night, with a tile pre-selected or nil. Set by
    /// `AppState`; called on the main actor by `WaterReminderManager` when a
    /// morning notification (or one of its quick answers) is tapped.
    @MainActor static var onOpen: (@MainActor (String, Symptom?) -> Void)?

    static func notificationId(eventId: String) -> String {
        notificationPrefix + eventId
    }

    /// The four quick answers on press and hold. Each opens the app, so a
    /// mis-tap at the lock screen only pre-selects a tile; it never builds a
    /// plan by itself.
    static func category() -> UNNotificationCategory {
        let actions = actionOrder.compactMap { id -> UNNotificationAction? in
            guard let symptom = actionIds[id] else { return nil }
            return UNNotificationAction(identifier: id, title: "\(symptom.emoji) \(symptom.label)",
                                        options: [.foreground])
        }
        return UNNotificationCategory(identifier: categoryId, actions: actions,
                                      intentIdentifiers: [], options: [])
    }

    /// The morning notification for a night, firing at its morning time.
    static func notificationRequest(eventId: String, nightEnd: Date,
                                    calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notificationTitle
        content.body = notificationBody
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["eventId": eventId]
        let morning = morningTime(nightEnd: nightEnd, calendar: calendar)
        // With the calendar and time zone attached the components name one
        // instant, the computed morning time, rather than a wall-clock time.
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: morning)
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: notificationId(eventId: eventId), content: content,
                                     trigger: trigger)
    }

    /// What a tapped notification opens: its night and the tile its action
    /// pre-selects (nil for the default tap). Nil unless it is a morning
    /// notification that names a night.
    static func checkInRequest(categoryId category: String, eventId: String?,
                               actionId: String) -> (eventId: String, preselected: Symptom?)? {
        guard category == Self.categoryId, let eventId, !eventId.isEmpty,
              actionId != UNNotificationDismissActionIdentifier else { return nil }
        return (eventId, symptom(forAction: actionId))
    }

    // MARK: - Server answer

    /// Reads `requestReport`'s answer to a `morning` request: `{morning,
    /// remaining}` or `{pending: true}`. `remaining` is nil when absent or
    /// null (Pro). Throws when `morning` is there but can't be read as a plan.
    static func response(from result: [String: Any], eventId: String) throws -> Response {
        let remaining = result["remaining"] as? Int
        guard let doc = result["morning"], !(doc is NSNull) else {
            return (record: nil, pending: result["pending"] as? Bool == true, remaining: remaining)
        }
        let record = try MorningRecord(eventId: eventId, serverJSON: planFields(doc))
        return (record: record, pending: false, remaining: remaining)
    }

    /// Only the fields `MorningDoc` reads, so nothing else stored in the doc
    /// (a value JSON can't hold) can spoil the plan.
    static func planFields(_ doc: Any) -> Any {
        guard let fields = doc as? [String: Any] else { return doc }
        let wanted: Set<String> = ["symptoms", "severity", "safety", "plan", "created_at"]
        return fields.filter { wanted.contains($0.key) }
    }

    // MARK: - Restoring plans

    /// How far back a fresh install pulls this account's plans from the server.
    static let restoreWindowDays = 30

    /// A stored `night_recoveries/{eventId}` doc as a plan. Nil for an old
    /// recovery brief (or anything else that isn't a morning plan) and for a
    /// doc that can't be read.
    static func restoredPlan(eventId: String, doc: [String: Any]) -> MorningRecord? {
        guard doc["type"] as? String == "morning" else { return nil }
        return try? MorningRecord(eventId: eventId, serverJSON: planFields(doc))
    }

    /// The server's plans merged into the ones on this phone. A plan already
    /// here stays exactly as it is; a server plan for a night this phone knows
    /// but has no plan for is added. A plan for a night that isn't here (it was
    /// deleted) is left out.
    static func mergedPlans(local: [String: MorningRecord], cloud: [MorningRecord],
                            nights: Set<String>) -> [String: MorningRecord] {
        var merged = local
        for record in cloud where merged[record.id] == nil && nights.contains(record.id) {
            merged[record.id] = record
        }
        return merged
    }

    /// Maps one request's result to what the app does next. The callable's
    /// status arrives as `RESOURCE_EXHAUSTED` (or `resource-exhausted`):
    /// free plans used up. `FAILED_PRECONDITION`: nothing in the library fits
    /// this check-in. Any other error, or an answer with neither a plan nor
    /// `pending`, is a failure.
    static func outcome(for error: Error?, response: Response?) -> MorningOutcome {
        if let error {
            let status = ((error as NSError).userInfo[FirebaseManager.callableStatusKey] as? String)?
                .uppercased().replacingOccurrences(of: "-", with: "_")
            switch status {
            case "RESOURCE_EXHAUSTED"?: return .locked
            case "FAILED_PRECONDITION"?: return .unavailable
            default: return .failed
            }
        }
        guard let response else { return .failed }
        if let record = response.record { return .ready(record) }
        return response.pending ? .poll : .failed
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
            "estimatedBacNow": safeBacNow(bacNow),
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

    /// `estimatedBacNow` only drives the don't-drive line, so a broken
    /// estimate errs toward showing it: a non-finite value becomes a small
    /// positive one instead of 0.
    static func safeBacNow(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0.01
    }
}
