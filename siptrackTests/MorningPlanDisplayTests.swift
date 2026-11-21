import Foundation
import Testing
@testable import siptrack

/// The check-in and plan views' pure pieces: the fixed copy, the titles picked
/// from severity and symptoms, the recap line, tick keys, the photo poll's
/// stop condition and which row a night's summary shows.
@MainActor
struct MorningPlanDisplayTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// A UTC date in November 2026 (the 20th is a Friday).
    private func nov(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func drink(_ type: String, _ quantity: Int, at date: Date) -> DrinkEntry {
        DrinkEntry(id: UUID().uuidString, eventId: "e", drinkTypeId: type, timestamp: date,
                   quantity: quantity, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
    }

    private func item(_ id: String, photo: String?) -> PlanPhotoItem {
        PlanPhotoItem(itemId: id, name: id, why: "Because.", when: nil, photoUrl: photo.flatMap { URL(string: $0) })
    }

    // MARK: - Verbatim copy

    @Test func checkInCopyIsVerbatim() {
        #expect(MorningPlanDisplay.checkInTitle == "How are you feeling?")
        #expect(MorningPlanDisplay.checkInHint == "Pick all that fit")
        #expect(MorningPlanDisplay.checkInButton == "Get my plan")
        #expect(MorningPlanDisplay.disclosure == "Sent to Anthropic with your night details to build your plan.")
        #expect(MorningPlanDisplay.tomorrowLine == "Recovery plan: tomorrow morning")
    }

    @Test func safetyLinesAreVerbatimAndInOrder() {
        let both = MorningPlanDisplay.safetyLines(PlanSafety(dontDrive: true, medicalHelp: true))
        #expect(both == [
            "Alcohol may still be in your system. Don't drive this morning.",
            "Can't keep water down for hours, or confused and hard to wake? Get medical help.",
        ])
        #expect(MorningPlanDisplay.safetyLines(PlanSafety(dontDrive: false, medicalHelp: true))
                == ["Can't keep water down for hours, or confused and hard to wake? Get medical help."])
        #expect(MorningPlanDisplay.safetyLines(PlanSafety(dontDrive: false, medicalHelp: false)).isEmpty)
    }

    // MARK: - Severity and symptoms

    @Test func heavyNightsAreRecoveryMode() {
        #expect(MorningPlanDisplay.label(severity: "heavy") == "YOUR MORNING · RECOVERY MODE")
        #expect(MorningPlanDisplay.label(severity: "very_heavy") == "YOUR MORNING · RECOVERY MODE")
        #expect(MorningPlanDisplay.label(severity: "moderate") == "YOUR RECOVERY PLAN")
        #expect(MorningPlanDisplay.label(severity: "light") == "YOUR RECOVERY PLAN")
        #expect(!MorningPlanDisplay.isRecoveryMode(severity: "something_new"))
    }

    @Test func firstFoodOnlyAfterAHeavyNightWithNausea() {
        #expect(MorningPlanDisplay.isFirstFood(severity: "heavy", symptoms: [.nausea, .dizzy]))
        #expect(MorningPlanDisplay.isFirstFood(severity: "very_heavy", symptoms: [.nausea]))
        #expect(!MorningPlanDisplay.isFirstFood(severity: "heavy", symptoms: [.headache]))
        #expect(!MorningPlanDisplay.isFirstFood(severity: "moderate", symptoms: [.nausea]))
    }

    @Test func breakfastTitleCarriesTheTime() {
        #expect(MorningPlanDisplay.breakfastTitle(when: "around 10:30", firstFood: false) == "BREAKFAST · AROUND 10:30")
        #expect(MorningPlanDisplay.breakfastTitle(when: nil, firstFood: false) == "BREAKFAST")
        #expect(MorningPlanDisplay.breakfastTitle(when: "  ", firstFood: false) == "BREAKFAST")
        #expect(MorningPlanDisplay.breakfastTitle(when: "around 10:30", firstFood: true)
                == "FIRST FOOD · WHEN IT STAYS DOWN")
    }

    @Test func fallbackGetsItsQuestion() {
        #expect(MorningPlanDisplay.fallbackLine(title: "Plain toast and broth instead.", firstFood: false)
                == "Stomach off? Plain toast and broth instead.")
        #expect(MorningPlanDisplay.fallbackLine(title: "Galletas saladas.", firstFood: true)
                == "Can't face it yet? Galletas saladas.")
        // The model asked its own question: not asked twice.
        #expect(MorningPlanDisplay.fallbackLine(title: "Stomach off? Try toast.", firstFood: false)
                == "Stomach off? Try toast.")
    }

    @Test func skipLineJoinsTitleAndReason() {
        #expect(MorningPlanDisplay.skipLine(title: "Hair of the dog", why: "It just pushes the hangover to later.")
                == "Hair of the dog. It just pushes the hangover to later.")
        #expect(MorningPlanDisplay.skipLine(title: "Hair of the dog.", why: "It backfires.")
                == "Hair of the dog. It backfires.")
        #expect(MorningPlanDisplay.skipLine(title: "Greasy food", why: " ") == "Greasy food")
    }

    // MARK: - Ticks and photos

    @Test func tickKeysArePerNightAndItem() {
        #expect(MorningPlanDisplay.tickKey(eventId: "night-1", item: "eggs-on-toast")
                == "morningTick.night-1.eggs-on-toast")
        #expect(MorningPlanDisplay.tickKey(eventId: "night-1", item: "Big glass of water")
                != MorningPlanDisplay.tickKey(eventId: "night-2", item: "Big glass of water"))
    }

    @Test func pollStopsOnceEveryPhotoIsThere() {
        #expect(MorningPlanDisplay.hasMissingPhotos(.sample))
        var plan = MorningPlan.sample
        plan.breakfast = item("eggs", photo: "https://example.com/eggs.jpg")
        plan.activities = [item("walk", photo: "https://example.com/walk.jpg"), item("nap", photo: nil)]
        #expect(MorningPlanDisplay.hasMissingPhotos(plan))
        plan.activities[1] = item("nap", photo: "https://example.com/nap.jpg")
        #expect(!MorningPlanDisplay.hasMissingPhotos(plan))
        #expect(MorningPlanDisplay.photoPollSeconds * MorningPlanDisplay.photoPollAttempts == 60)
    }

    // MARK: - Check-in header

    @Test func labelNamesTheNightsWeekday() {
        #expect(MorningPlanDisplay.checkInLabel(nightStart: nov(20, 21), calendar: Self.utc)
                == "MORNING AFTER · FRIDAY NIGHT")
    }

    @Test func aSmallHoursStartBelongsToTheEveningBefore() {
        #expect(MorningPlanDisplay.checkInLabel(nightStart: nov(21, 0, 30), calendar: Self.utc)
                == "MORNING AFTER · FRIDAY NIGHT")
        #expect(MorningPlanDisplay.checkInLabel(nightStart: nov(21, 5), calendar: Self.utc)
                == "MORNING AFTER · SATURDAY NIGHT")
    }

    @Test func recapReadsLikeTheMockup() {
        #expect(MorningPlanDisplay.recap(drinks: 8, topDrink: "tequila", ended: "2:40 AM", waters: 1)
                == "8 drinks · mostly tequila · ended 2:40 AM · 1 water")
        #expect(MorningPlanDisplay.recap(drinks: 1, topDrink: "beer", ended: "11:40 PM", waters: 0)
                == "1 drink · ended 11:40 PM · no water")
        #expect(MorningPlanDisplay.recap(drinks: 3, topDrink: nil, ended: "1:00 AM", waters: 2)
                == "3 drinks · ended 1:00 AM · 2 water")
    }

    @Test func topDrinkCountsServings() {
        let entries = [
            drink("beer", 1, at: nov(20, 21)),
            drink("tequila", 2, at: nov(20, 22)),
            drink("tequila", 3, at: nov(20, 23)),
            drink("beer", 2, at: nov(21, 0)),
        ]
        #expect(MorningPlanDisplay.topDrinkName(entries: entries, drinkTypes: DrinkType.presets) == "tequila")
    }

    @Test func topDrinkTieGoesToTheFirstLogged() {
        let entries = [
            drink("red-wine", 2, at: nov(20, 22)),
            drink("ipa", 2, at: nov(20, 21)),
        ]
        #expect(MorningPlanDisplay.topDrinkName(entries: entries, drinkTypes: DrinkType.presets) == "IPA")
    }

    @Test func topDrinkIsNilWhenTheTypeIsUnknown() {
        #expect(MorningPlanDisplay.topDrinkName(entries: [drink("deleted-custom", 4, at: nov(20, 21))],
                                                drinkTypes: DrinkType.presets) == nil)
        #expect(MorningPlanDisplay.topDrinkName(entries: [], drinkTypes: DrinkType.presets) == nil)
    }

    @Test func casualNamesKeepAcronyms() {
        #expect(MorningPlanDisplay.casualName("Red Wine") == "red wine")
        #expect(MorningPlanDisplay.casualName("IPA") == "IPA")
        #expect(MorningPlanDisplay.casualName("tequila") == "tequila")
    }

    // MARK: - Summary row

    @Test func oldReportsKeepTheOldCard() {
        #expect(MorningSummaryRow.resolve(hasOldReport: true, hasPlan: true, isCheckInNight: true,
                                          isCheckInNightLater: false) == .oldReport)
    }

    @Test func aPlanBeatsTheCheckIn() {
        #expect(MorningSummaryRow.resolve(hasOldReport: false, hasPlan: true, isCheckInNight: false,
                                          isCheckInNightLater: false) == .plan)
    }

    @Test func checkInNightBeforeAndAfterItsMorning() {
        #expect(MorningSummaryRow.resolve(hasOldReport: false, hasPlan: false, isCheckInNight: false,
                                          isCheckInNightLater: true) == .tomorrowMorning)
        #expect(MorningSummaryRow.resolve(hasOldReport: false, hasPlan: false, isCheckInNight: true,
                                          isCheckInNightLater: false) == .checkIn)
    }

    @Test func anyOtherNightHidesTheCard() {
        #expect(MorningSummaryRow.resolve(hasOldReport: false, hasPlan: false, isCheckInNight: false,
                                          isCheckInNightLater: false) == .hidden)
    }

    // MARK: - Pending check-in

    @Test func pendingCheckInIsIdentifiedByItsNight() {
        let headache = PendingCheckIn(eventId: "friday", preselected: .headache)
        #expect(headache.id == "friday")
        #expect(headache == PendingCheckIn(eventId: "friday", preselected: .headache))
        #expect(headache != PendingCheckIn(eventId: "friday", preselected: nil))
    }
}
