import Foundation

/// Dates in the UI read in English whatever language the phone is set to.
///
/// `DateFormatter` and `Date.FormatStyle` both default to `Locale.current`, so
/// on a Spanish phone an `"MMMM"` pattern renders "noviembre" and `EEEE`
/// renders "lunes" — in the middle of screens whose every other word is
/// English. There is no app-wide switch for this: each formatter has to name
/// the locale, which is exactly why it drifted in the first place.
///
/// Only month and weekday names go through here. Times are deliberately left
/// on the device locale, so a phone set to 24-hour clock keeps showing 21:30
/// rather than being forced to 9:30 PM.
enum AppDates {
    /// The locale every month and weekday name is rendered in.
    ///
    /// `en_US_POSIX` rather than `en_US`: it is fixed, so a future iOS cannot
    /// quietly restyle these strings the way a user-facing locale can.
    static let locale = Locale(identifier: "en_US_POSIX")

    /// A formatter for a fixed pattern, with English month and weekday names.
    static func formatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = dateFormat
        return formatter
    }

    /// A formatter for one of the system date styles, in English.
    static func formatter(
        dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style = .none
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter
    }
}

extension Date.FormatStyle {
    /// English months and weekdays, for `Text(date, format:)` call sites.
    var english: Date.FormatStyle { locale(AppDates.locale) }
}
