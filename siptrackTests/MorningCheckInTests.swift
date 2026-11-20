import Foundation
import Testing
import UserNotifications
@testable import siptrack

@MainActor
struct MorningCheckInTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// A UTC date in November 2026 (the 20th is a Friday).
    private func nov(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: - morningTime

    @Test func endAt0240GivesSameDay0940() {
        #expect(MorningCheckIn.morningTime(nightEnd: nov(21, 2, 40), calendar: Self.utc) == nov(21, 9, 40))
    }

    @Test func endAt2300ClampsTheNext0600To0800() {
        #expect(MorningCheckIn.morningTime(nightEnd: nov(20, 23), calendar: Self.utc) == nov(21, 8))
    }

    @Test func endAt0900Gives1600() {
        #expect(MorningCheckIn.morningTime(nightEnd: nov(21, 9), calendar: Self.utc) == nov(21, 16))
    }

    @Test func aDSTChangeNightStillAddsSevenElapsedHours() throws {
        // US clocks jump from 02:00 to 03:00 on 8 March 2026.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let end = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30)))
        let morning = MorningCheckIn.morningTime(nightEnd: end, calendar: newYork)
        #expect(morning.timeIntervalSince(end) == 7 * 3600)
        // 7 elapsed hours from 01:30 EST read 09:30 EDT on the wall clock, not 08:30.
        #expect(newYork.component(.hour, from: morning) == 9)
        #expect(newYork.component(.minute, from: morning) == 30)
    }

    // MARK: - shouldNotify

    private func notify(drinks: Double = 5, signedIn: Bool = true, ai: Bool = true,
                        pro: Bool = false, left: Int = 3) -> Bool {
        MorningCheckIn.shouldNotify(standardDrinks: drinks, signedIn: signedIn, aiEnabled: ai,
                                    isPro: pro, freePlansLeft: left)
    }

    @Test func noNotificationBelowThreeStandardDrinks() {
        #expect(notify(drinks: 2.9) == false)
        #expect(notify(drinks: 0) == false)
        #expect(notify(drinks: 3) == true)
    }

    @Test func noNotificationWhenAIIsOffOrSignedOut() {
        #expect(notify(ai: false) == false)
        #expect(notify(signedIn: false) == false)
        #expect(notify(signedIn: false, pro: true) == false)
    }

    @Test func noNotificationForAFreeUserWithNoPlansLeft() {
        #expect(notify(pro: false, left: 0) == false)
    }

    @Test func proGetsTheNotificationWithNoFreePlansLeft() {
        #expect(notify(pro: true, left: 0) == true)
    }

    @Test func freeUserWithOnePlanLeftGetsTheNotification() {
        #expect(notify(pro: false, left: 1) == true)
    }

    // MARK: - checkInEventId

    private func night(_ id: String, start: Date, end: Date?, aiReport: String? = nil) -> NightEvent {
        NightEvent(id: id, startTime: start, endTime: end, drivingMode: false, aiReport: aiReport, createdAt: start)
    }

    /// Friday night, ended 02:40 Saturday: its morning time is 09:40 UTC.
    private var friday: NightEvent { night("friday", start: nov(20, 22), end: nov(21, 2, 40)) }

    private func checkIn(_ events: [NightEvent], now: Date, planned: Set<String> = [],
                         drinks: Double = 5) -> String? {
        MorningCheckIn.checkInEventId(events: events, standardDrinks: { _ in drinks },
                                      plannedIds: planned, now: now, calendar: Self.utc)
    }

    @Test func noCheckInBeforeTheMorningTime() {
        #expect(checkIn([friday], now: nov(21, 2, 41)) == nil)
        #expect(checkIn([friday], now: nov(21, 9, 39)) == nil)
    }

    @Test func checkInFromTheMorningTime() {
        #expect(checkIn([friday], now: nov(21, 9, 40)) == "friday")
        #expect(checkIn([friday], now: nov(21, 18)) == "friday")
    }

    @Test func noCheckInOnceANewerNightHasStarted() {
        let active = night("saturday", start: nov(21, 20), end: nil)
        #expect(checkIn([active, friday], now: nov(21, 21)) == nil)
        let ended = night("saturday", start: nov(21, 20), end: nov(21, 23))
        #expect(checkIn([ended, friday], now: nov(21, 23, 30)) == nil)
        // The newer night gets its own check-in at its own morning time.
        #expect(checkIn([friday, ended], now: nov(22, 8)) == "saturday")
    }

    @Test func noCheckInForAPlannedNight() {
        #expect(checkIn([friday], now: nov(21, 10), planned: ["friday"]) == nil)
    }

    @Test func noCheckInForNightsWithAnOldReportOrBrief() {
        // Callers fold old night-report and recovery-brief ids into plannedIds.
        let briefIds: Set<String> = ["friday"]
        #expect(checkIn([friday], now: nov(21, 10), planned: briefIds) == nil)
        // An old night report on the event itself is also refused directly.
        let reported = night("friday", start: nov(20, 22), end: nov(21, 2, 40), aiReport: "ALCOHOL LOGGED: ...")
        #expect(checkIn([reported], now: nov(21, 10)) == nil)
    }

    @Test func noCheckInForAZeroDrinkNight() {
        #expect(checkIn([friday], now: nov(21, 10), drinks: 0) == nil)
        #expect(checkIn([], now: nov(21, 10)) == nil)
    }

    @Test func defaultCalendarSignatureWorks() {
        let end = Date(timeIntervalSince1970: 1_795_000_000)
        let ended = night("n", start: end.addingTimeInterval(-4 * 3600), end: end)
        let soon = MorningCheckIn.checkInEventId(events: [ended], standardDrinks: { _ in 4 },
                                                 plannedIds: [], now: end.addingTimeInterval(3600))
        let nextDay = MorningCheckIn.checkInEventId(events: [ended], standardDrinks: { _ in 4 },
                                                    plannedIds: [], now: end.addingTimeInterval(24 * 3600))
        #expect(soon == nil)
        #expect(nextDay == "n")
    }

    // MARK: - toggle

    @Test func selectingFineClearsTheOthers() {
        #expect(MorningCheckIn.toggle(.fine, in: [.headache, .nausea]) == [.fine])
    }

    @Test func selectingASymptomClearsFine() {
        #expect(MorningCheckIn.toggle(.nausea, in: [.fine]) == [.nausea])
        #expect(MorningCheckIn.toggle(.dizzy, in: [.headache]) == [.headache, .dizzy])
    }

    @Test func selectingASelectedSymptomDeselectsIt() {
        #expect(MorningCheckIn.toggle(.headache, in: [.headache, .nausea]) == [.nausea])
        #expect(MorningCheckIn.toggle(.fine, in: [.fine]).isEmpty)
    }

    // MARK: - Notification actions

    @Test func eachActionIdMapsToItsSymptom() {
        #expect(MorningCheckIn.categoryId == "siptrack.morning")
        #expect(MorningCheckIn.actionIds.count == 4)
        #expect(MorningCheckIn.symptom(forAction: "morning.headache") == .headache)
        #expect(MorningCheckIn.symptom(forAction: "morning.nausea") == .nausea)
        #expect(MorningCheckIn.symptom(forAction: "morning.wrecked") == .wrecked)
        #expect(MorningCheckIn.symptom(forAction: "morning.fine") == .fine)
    }

    @Test func theDefaultTapPreselectsNothing() {
        #expect(MorningCheckIn.symptom(forAction: UNNotificationDefaultActionIdentifier) == nil)
        #expect(MorningCheckIn.symptom(forAction: UNNotificationDismissActionIdentifier) == nil)
    }

    // MARK: - payload

    private func tequila(_ id: String, minute: Int, eventId: String = "friday") -> DrinkEntry {
        DrinkEntry(id: id, eventId: eventId, drinkTypeId: "tequila",
                   timestamp: nov(20, 22).addingTimeInterval(Double(minute) * 60), quantity: 1, comment: nil,
                   volumeOverrideMl: nil, abvOverride: nil)
    }

    /// Six tequilas from 22:00 to 01:20, two waters and a snack, checked in at
    /// 03:30 Saturday while alcohol is still in the system.
    private func fridayPayload(symptoms: Set<Symptom> = [.nausea, .headache], countryCode: String? = nil,
                               region: String? = "US") -> [String: Any] {
        var profile = UserProfile()
        profile.countryCode = countryCode
        return MorningCheckIn.payload(
            event: friday, entries: fridayEntries, waters: fridayWaters, foods: fridayFoods,
            drinkTypes: DrinkType.presets, profile: profile, symptoms: symptoms, now: nov(21, 3, 30),
            calendar: Self.utc, region: region
        )
    }

    private var fridayEntries: [DrinkEntry] {
        (0..<6).map { tequila("t\($0)", minute: $0 * 40) } + [tequila("elsewhere", minute: 10, eventId: "other")]
    }

    private var fridayWaters: [WaterEntry] {
        [WaterEntry(id: "w1", eventId: "friday", timestamp: nov(20, 23), volumeMl: 250),
         WaterEntry(id: "w2", eventId: "friday", timestamp: nov(21, 1), volumeMl: 250)]
    }

    private var fridayFoods: [FoodEntry] {
        [FoodEntry(id: "f1", eventId: "friday", type: .snack, timestamp: nov(20, 22, 30))]
    }

    @Test func payloadCarriesTheCheckInAndNightFacts() throws {
        let payload = fridayPayload()
        #expect(payload["symptoms"] as? [String] == ["headache", "nausea"])
        #expect(payload["checkInHour"] as? Int == 3)
        #expect(payload["weekday"] as? Int == 7)   // Saturday
        #expect(payload["endHour"] as? Int == 2)
        #expect(payload["durationMinutes"] as? Int == 280)
        #expect(payload["waterMl"] as? Double == 500)
        #expect(payload["foodEntryCount"] as? Int == 1)
        #expect(payload["stomachState"] as? String == "empty")
        #expect(payload["userSex"] as? String == "Male")
        #expect((payload["peakBac"] as? Double ?? 0) > 0)

        let bacNow = try #require(payload["estimatedBacNow"] as? Double)
        let nightEntries = fridayEntries.filter { $0.eventId == "friday" }
        let expected = BACCalculator.currentBAC(
            entries: nightEntries, waterEntries: fridayWaters, drinkTypes: DrinkType.presets,
            profile: UserProfile(), eventStart: friday.startTime, stomachState: .empty,
            stomachStateTimestamp: nil, foodEntries: fridayFoods, asOf: nov(21, 3, 30)
        )
        #expect(bacNow == expected)
        #expect(bacNow > 0)

        let dose = try #require(payload["alcoholDose"] as? [String: Any])
        let drinks = try #require(payload["drinks"] as? [[String: Any]])
        #expect(dose["loggedServings"] as? Int == 6)   // the other night's drink is left out
        #expect(drinks.count == 1)
        #expect(drinks.first?["name"] as? String == "Tequila")
        #expect(JSONSerialization.isValidJSONObject(payload))
    }

    @Test func fineIsNeverSentAlongsideOtherSymptoms() {
        #expect(fridayPayload(symptoms: [.fine, .headache])["symptoms"] as? [String] == ["headache"])
        #expect(fridayPayload(symptoms: [.fine])["symptoms"] as? [String] == ["fine"])
    }

    @Test func countryPrefersTheProfileThenTheDeviceRegion() {
        #expect(fridayPayload(countryCode: "MX", region: "US")["country"] as? String == "MX")
        #expect(fridayPayload(countryCode: "mx", region: nil)["country"] as? String == "MX")
        #expect(fridayPayload(countryCode: nil, region: "US")["country"] as? String == "US")
        #expect(fridayPayload(countryCode: "", region: "ES")["country"] as? String == "ES")
    }

    @Test func countryIsOmittedUnlessItIsTwoUppercaseLetters() {
        // "419" is Latin America in UN M.49, not a country; the server would refuse it.
        #expect(!fridayPayload(countryCode: nil, region: "419").keys.contains("country"))
        #expect(!fridayPayload(countryCode: nil, region: nil).keys.contains("country"))
        #expect(!fridayPayload(countryCode: "USA", region: "1").keys.contains("country"))
    }

    @Test func countryFallsBackToLocaleCurrentRegionWhenTheProfileHasNone() {
        var profile = UserProfile()
        profile.countryCode = nil
        let payload = MorningCheckIn.payload(
            event: friday, entries: fridayEntries, waters: fridayWaters, foods: fridayFoods,
            drinkTypes: DrinkType.presets, profile: profile, symptoms: [.wrecked], now: nov(21, 10)
        )
        let region = Locale.current.region?.identifier
        if let region, region.range(of: "^[A-Z]{2}$", options: .regularExpression) != nil {
            #expect(payload["country"] as? String == region)
        } else {
            #expect(!payload.keys.contains("country"))
        }
    }
}
