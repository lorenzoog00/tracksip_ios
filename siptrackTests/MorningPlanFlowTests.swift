import Foundation
import Testing
import UserNotifications
@testable import siptrack

/// The morning-plan flow's pure pieces: how a request's result maps to what the
/// app does next, the notification and its quick answers, reading the server's
/// answer, and the local free-plan count. The network is stubbed by passing
/// results in.
@MainActor
struct MorningPlanFlowTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// A UTC date in November 2026 (the 20th is a Friday).
    private func nov(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private var record: MorningRecord {
        MorningRecord(id: "friday", symptoms: [.headache], severity: "heavy",
                      safety: PlanSafety(dontDrive: true, medicalHelp: false), plan: .sample,
                      createdAt: Date(timeIntervalSince1970: 1_795_161_600))
    }

    /// A refusal as `FirebaseManager.callFunction` throws it: the callable's
    /// status in userInfo.
    private func callableError(_ status: String, code: Int = 429) -> NSError {
        NSError(domain: "FirebaseManager", code: code, userInfo: [
            NSLocalizedDescriptionKey: "Refused.",
            FirebaseManager.callableStatusKey: status,
        ])
    }

    // MARK: - outcome

    @Test func freePlansUsedUpMapsToLocked() {
        #expect(MorningCheckIn.outcome(for: callableError("RESOURCE_EXHAUSTED"), response: nil) == .locked)
        // The SDK spelling, in case a client library ever passes it through.
        #expect(MorningCheckIn.outcome(for: callableError("resource-exhausted"), response: nil) == .locked)
    }

    @Test func pendingMapsToPoll() {
        let pending: MorningCheckIn.Response = (record: nil, pending: true, remaining: nil)
        #expect(MorningCheckIn.outcome(for: nil, response: pending) == .poll)
    }

    @Test func nothingInTheLibraryMapsToUnavailable() {
        #expect(MorningCheckIn.outcome(for: callableError("FAILED_PRECONDITION", code: 400), response: nil) == .unavailable)
        #expect(MorningCheckIn.outcome(for: callableError("failed-precondition", code: 400), response: nil) == .unavailable)
    }

    @Test func otherErrorsMapToFailed() {
        #expect(MorningCheckIn.outcome(for: callableError("INTERNAL", code: 500), response: nil) == .failed)
        #expect(MorningCheckIn.outcome(for: callableError("INVALID_ARGUMENT", code: 400), response: nil) == .failed)
        #expect(MorningCheckIn.outcome(for: URLError(.notConnectedToInternet), response: nil) == .failed)
        // The AI-consent guard and an undeployed function carry no callable status.
        let consent = NSError(domain: "FirebaseManager", code: 403,
                              userInfo: [NSLocalizedDescriptionKey: "Enable AI reports in Profile."])
        #expect(MorningCheckIn.outcome(for: consent, response: nil) == .failed)
    }

    @Test func aPlanMapsToReady() {
        let answer: MorningCheckIn.Response = (record: record, pending: false, remaining: 2)
        #expect(MorningCheckIn.outcome(for: nil, response: answer) == .ready(record))
    }

    @Test func anAnswerWithNeitherPlanNorPendingIsAFailure() {
        let empty: MorningCheckIn.Response = (record: nil, pending: false, remaining: 1)
        #expect(MorningCheckIn.outcome(for: nil, response: empty) == .failed)
        #expect(MorningCheckIn.outcome(for: nil, response: nil) == .failed)
    }

    @Test func anErrorWinsOverAnyResponse() {
        let answer: MorningCheckIn.Response = (record: record, pending: false, remaining: 0)
        #expect(MorningCheckIn.outcome(for: callableError("RESOURCE_EXHAUSTED"), response: answer) == .locked)
    }

    // MARK: - Notification

    @Test func theNotificationFiresAtTheMorningTime() throws {
        let end = nov(21, 2, 40)
        let request = MorningCheckIn.notificationRequest(eventId: "friday", nightEnd: end, calendar: Self.utc)
        #expect(request.identifier == "siptrack.morning-friday")
        #expect(request.content.categoryIdentifier == "siptrack.morning")
        #expect(request.content.title == "Rough night? 🥴")
        #expect(request.content.body == "Tell us how you feel and get your recovery plan.")
        #expect(request.content.userInfo["eventId"] as? String == "friday")

        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats == false)
        let fires = try #require(Self.utc.date(from: trigger.dateComponents))
        #expect(fires == MorningCheckIn.morningTime(nightEnd: end, calendar: Self.utc))
        #expect(fires == nov(21, 9, 40))
    }

    @Test func aLateEndFiresAtEightTheNextMorning() throws {
        let request = MorningCheckIn.notificationRequest(eventId: "n", nightEnd: nov(20, 23), calendar: Self.utc)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(Self.utc.date(from: trigger.dateComponents) == nov(21, 8))
    }

    @Test func notificationIdsNameTheNight() {
        #expect(MorningCheckIn.notificationId(eventId: "abc") == "siptrack.morning-abc")
        #expect(MorningCheckIn.notificationId(eventId: "abc").hasPrefix(MorningCheckIn.notificationPrefix))
    }

    @Test func theNotificationIsOnlyScheduledForAMorningStillAhead() {
        let end = nov(21, 2, 40)
        #expect(MorningCheckIn.notificationDate(nightEnd: end, now: end, calendar: Self.utc) == nov(21, 9, 40))
        #expect(MorningCheckIn.notificationDate(nightEnd: end, now: nov(21, 9, 39), calendar: Self.utc) == nov(21, 9, 40))
        #expect(MorningCheckIn.notificationDate(nightEnd: end, now: nov(21, 9, 40), calendar: Self.utc) == nil)
        #expect(MorningCheckIn.notificationDate(nightEnd: end, now: nov(25, 9), calendar: Self.utc) == nil)
    }

    @Test func theCategoryHasTheFourQuickAnswersInOrder() {
        let category = MorningCheckIn.category()
        let titles = category.actions.map(\.title)
        let ids = category.actions.map(\.identifier)
        let allForeground = category.actions.allSatisfy { $0.options.contains(.foreground) }
        let tiles = ids.map { MorningCheckIn.symptom(forAction: $0) }
        #expect(category.identifier == "siptrack.morning")
        #expect(titles == ["🤕 Headache", "🤢 Nausea", "😴 Wrecked", "💪 I'm fine"])
        #expect(ids == ["morning.headache", "morning.nausea", "morning.wrecked", "morning.fine"])
        #expect(allForeground)
        #expect(tiles == [.headache, .nausea, .wrecked, .fine])
    }

    // MARK: - Notification response

    @Test func aTapOpensTheCheckInWithNothingPreselected() {
        let open = MorningCheckIn.checkInRequest(categoryId: "siptrack.morning", eventId: "friday",
                                                 actionId: UNNotificationDefaultActionIdentifier)
        #expect(open?.eventId == "friday")
        #expect(open?.preselected == nil)
    }

    @Test func aQuickAnswerPreselectsItsTile() {
        let open = MorningCheckIn.checkInRequest(categoryId: "siptrack.morning", eventId: "friday",
                                                 actionId: "morning.nausea")
        #expect(open?.eventId == "friday")
        #expect(open?.preselected == .nausea)
    }

    @Test func otherNotificationsOpenNothing() {
        // The water reminder: no category, but it does carry an event id.
        let water = MorningCheckIn.checkInRequest(categoryId: "", eventId: "friday",
                                                  actionId: UNNotificationDefaultActionIdentifier)
        let noNight = MorningCheckIn.checkInRequest(categoryId: "siptrack.morning", eventId: nil,
                                                    actionId: UNNotificationDefaultActionIdentifier)
        let emptyNight = MorningCheckIn.checkInRequest(categoryId: "siptrack.morning", eventId: "",
                                                       actionId: "morning.fine")
        let dismissed = MorningCheckIn.checkInRequest(categoryId: "siptrack.morning", eventId: "friday",
                                                      actionId: UNNotificationDismissActionIdentifier)
        #expect(water?.eventId == nil)
        #expect(noNight?.eventId == nil)
        #expect(emptyNight?.eventId == nil)
        #expect(dismissed?.eventId == nil)
    }

    // MARK: - Server answer

    private func serverDoc() throws -> [String: Any] {
        let json = """
        {
          "type": "morning", "version": 2, "created_at": 1795161600000,
          "symptoms": ["headache"], "severity": "heavy",
          "safety": {"dontDrive": true, "medicalHelp": false},
          "plan": {
            "headline": "Water first, food in an hour.",
            "rightNow": [{"icon": "drop.fill", "title": "Water", "why": "Six tequilas, one water."}],
            "breakfast": {"itemId": "lib_1", "name": "Toast", "why": "Easy on you.", "when": "around 10", "photoUrl": null},
            "fallback": null,
            "activities": [{"itemId": "lib_2", "name": "Walk", "why": "Daylight.", "photoUrl": null}],
            "skip": null
          },
          "items": ["lib_1", "lib_2"]
        }
        """
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func aPlanAnswerCarriesTheRecordAndTheFreePlansLeft() throws {
        let doc = try serverDoc()
        let answer = try MorningCheckIn.response(from: ["morning": doc, "remaining": 2], eventId: "friday")
        let plan = try #require(answer.record)
        #expect(plan.id == "friday")
        #expect(plan.symptoms == [.headache])
        #expect(plan.plan.breakfast.name == "Toast")
        #expect(answer.pending == false)
        #expect(answer.remaining == 2)
    }

    @Test func proGetsNoRemainingCount() throws {
        let doc = try serverDoc()
        let answer = try MorningCheckIn.response(from: ["morning": doc, "remaining": NSNull()], eventId: "friday")
        #expect(answer.record?.id == "friday")
        #expect(answer.remaining == nil)
    }

    @Test func aPendingAnswerHasNoRecord() throws {
        let answer = try MorningCheckIn.response(from: ["pending": true], eventId: "friday")
        #expect(answer.record == nil)
        #expect(answer.pending)
        #expect(answer.remaining == nil)
    }

    @Test func anUnreadablePlanThrows() {
        #expect(throws: (any Error).self) {
            _ = try MorningCheckIn.response(from: ["morning": ["plan": "nope"]], eventId: "friday")
        }
    }

    @Test func aStoredValueJSONCantHoldDoesNotSpoilThePlan() throws {
        // A Firestore snapshot can hold values JSON can't (a Timestamp, say).
        var doc = try serverDoc()
        doc["reviewedAt"] = Date()
        let answer = try MorningCheckIn.response(from: ["morning": doc], eventId: "friday")
        #expect(answer.record?.plan.headline == "Water first, food in an hour.")
    }

    // MARK: - Free plans

    @Test func freeUsersGetThreePlansAMonth() {
        #expect(MorningCheckIn.freeMonthlyPlans == 3)
        #expect(MorningCheckIn.freePlansLeft(allowance: [:], now: nov(20, 12)) == 3)
        // Last month's count doesn't carry over.
        #expect(MorningCheckIn.freePlansLeft(allowance: ["2026-10": 0], now: nov(20, 12)) == 3)
    }

    @Test func theStoredCountIsReadForTheCurrentMonth() {
        #expect(MorningCheckIn.freePlansLeft(allowance: ["2026-11": 1], now: nov(20, 12)) == 1)
        #expect(MorningCheckIn.freePlansLeft(allowance: ["2026-11": -2], now: nov(20, 12)) == 0)
    }

    @Test func storingACountKeepsOnlyThisMonth() throws {
        #expect(MorningCheckIn.allowance(left: 2, now: nov(20, 12)) == ["2026-11": 2])
        #expect(MorningCheckIn.allowance(left: -1, now: nov(20, 12)) == ["2026-11": 0])
        // Locked: none left until the month turns.
        let locked = MorningCheckIn.allowance(left: 0, now: nov(20, 12))
        #expect(MorningCheckIn.freePlansLeft(allowance: locked, now: nov(30, 23)) == 0)
        let december = try #require(Self.utc.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 0)))
        #expect(MorningCheckIn.freePlansLeft(allowance: locked, now: december) == 3)
    }

    @Test func theQuotaMonthIsUTCLikeTheServer() {
        // 23:30 on 30 November in Mexico City (UTC-6) is already December in UTC.
        let lateInMexico = nov(30, 23, 30).addingTimeInterval(6 * 3600)
        #expect(MorningCheckIn.monthKey(for: lateInMexico) == "2026-12")
        #expect(MorningCheckIn.monthKey(for: nov(30, 23, 59)) == "2026-11")
    }
}
