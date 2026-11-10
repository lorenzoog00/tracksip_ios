import Foundation
import Testing
@testable import siptrack

struct AppDatesTests {
    /// Noon so that no time zone can shift it onto another day or month.
    private let date = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)
    )!

    private let englishWeekdays: Set<String> = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
        "Sunday"
    ]

    @Test func monthNamesAreEnglishWhateverThePhonesLanguageIs() {
        // The whole bug: `DateFormatter` defaults to `Locale.current`, so on a
        // Spanish phone the calendar header said "noviembre" and the month
        // comparison said "noviembre vs octubre", inside an English UI. The
        // test runs under whatever locale the simulator has, so it pins the
        // output rather than the locale.
        #expect(AppDates.formatter("MMMM").string(from: date) == "November")
        #expect(AppDates.formatter("MMM").string(from: date) == "Nov")
        #expect(AppDates.formatter("MMMM yyyy").string(from: date) == "November 2026")
    }

    @Test func allTwelveMonthsAreEnglish() {
        let expected = [
            "January", "February", "March", "April", "May", "June", "July",
            "August", "September", "October", "November", "December"
        ]
        #expect(AppDates.formatter("MMMM").monthSymbols == expected)
    }

    @Test func weekdayNamesAreEnglishToo() {
        // A screen reading "lunes, November 16" is worse than either language
        // on its own, so the weekday patterns go through the same locale.
        let weekday = AppDates.formatter("EEEE").string(from: date)
        #expect(englishWeekdays.contains(weekday), "weekday was “\(weekday)”")
    }

    @Test func theSwiftUIFormatStyleUsesTheSameLocale() {
        // `Text(date, format: .dateTime.month(...))` is a separate mechanism
        // from `DateFormatter` and localises independently, so it needs its own
        // check or half the screens drift back.
        #expect(date.formatted(.dateTime.month(.wide).english) == "November")
        #expect(date.formatted(.dateTime.month(.abbreviated).english) == "Nov")
    }

    @Test func aDateStyleFormatterIsEnglishWithoutNamingAPattern() {
        let text = AppDates.formatter(dateStyle: .medium).string(from: date)
        #expect(text.contains("Nov"), "medium date was “\(text)”")
    }

    @Test func timesAreLeftOnTheDevicesOwnClockPreference() {
        // Deliberate: forcing en_US here would push a phone set to a 24-hour
        // clock back to "9:30 PM". Only the names are ours to anglicise.
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        #expect(formatter.locale.identifier != AppDates.locale.identifier)
    }
}
