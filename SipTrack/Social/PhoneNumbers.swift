//
//  PhoneNumbers.swift
//  SipTrack
//
//  Phone numbers in, E.164 out. Friend finding matches on E.164 strings only, so
//  every number from the address book or the phone field goes through here first.
//

import Foundation
import PhoneNumberKit

/// A country the user can pick for their phone number.
nonisolated struct PhoneCountry: Identifiable, Hashable, Sendable {
    let region: String     // ISO 3166 code, "MX"
    let name: String       // in the user's language, "México"
    let dialCode: Int      // 52
    let flag: String       // "🇲🇽"
    var id: String { region }
}

enum PhoneNumbers {
    /// One parser for the whole app: building it loads the metadata JSON.
    /// PhoneNumberUtility is not marked Sendable, but after init it only reads its
    /// metadata, and its regex cache sits behind an NSLock, so sharing it across
    /// threads is safe.
    private nonisolated(unsafe) static let utility = PhoneNumberUtility()

    /// Any written form of a number, as E.164 ("+525512345678"), or nil when it is
    /// not a valid number. A number written without a country code is read as a
    /// number of `defaultRegion`, the user's own country.
    nonisolated static func normalize(_ raw: String, defaultRegion: String) -> String? {
        let cleaned = withoutFormatCharacters(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        guard cleaned.filter({ $0 == "+" || $0 == "＋" }).count <= 1 else { return nil }
        let hasPlus = cleaned.first == "+" || cleaned.first == "＋"
        let input = mexicanRewrite(digits: asciiDigits(cleaned), hasPlus: hasPlus, defaultRegion: defaultRegion)
            ?? cleaned
        guard let number = parse(input, region: defaultRegion) else { return nil }
        return utility.format(number, toType: .e164)
    }

    /// The region of an E.164 number: "+525512345678" → "MX".
    nonisolated static func region(ofE164 number: String) -> String? {
        guard number.hasPrefix("+"), let parsed = parse(number, region: "US") else { return nil }
        return utility.getRegionCode(of: parsed)
    }

    /// E.164 for a national number typed under a chosen country, or nil unless it
    /// is a valid number of that country.
    nonisolated static func e164(national: String, region: String) -> String? {
        let digits = asciiDigits(national)
        guard !digits.isEmpty, let dialCode = utility.countryCode(for: region) else { return nil }
        let input = mexicanRewrite(digits: digits, hasPlus: false, defaultRegion: region) ?? digits
        guard let number = parse(input, region: region), number.countryCode == dialCode else { return nil }
        return utility.format(number, toType: .e164)
    }

    /// An E.164 number for display: "+52 55 1234 5678". Anything that does not
    /// parse comes back unchanged.
    nonisolated static func formatted(_ e164: String) -> String {
        guard e164.hasPrefix("+"), let parsed = parse(e164, region: "US") else { return e164 }
        return utility.format(parsed, toType: .international)
    }

    /// As-you-type formatting for the phone field: "5512" → "55 12".
    nonisolated static func formattedPartial(_ typed: String, region: String) -> String {
        // PartialFormatter keeps state between calls, so each call gets its own.
        PartialFormatter(utility: utility, defaultRegion: region, withPrefix: true).formatPartial(typed)
    }

    /// Every country PhoneNumberKit knows, sorted by name in the user's language.
    static var countries: [PhoneCountry] { allCountries }

    /// The device's region when PhoneNumberKit knows it, else Mexico.
    static var defaultRegion: String {
        if let region = Locale.current.region?.identifier.uppercased(), isCountryCode(region) {
            return region
        }
        return "MX"
    }

    // MARK: - Private

    private static let allCountries: [PhoneCountry] = {
        let locale = Locale.current
        var seen = Set<String>()
        let regions = PhoneNumbers.utility.allCountries().filter { region in
            PhoneNumbers.isCountryCode(region) && seen.insert(region).inserted
        }
        return regions
            .compactMap { region -> PhoneCountry? in
                guard let dialCode = PhoneNumbers.utility.countryCode(for: region) else { return nil }
                return PhoneCountry(region: region,
                                    name: locale.localizedString(forRegionCode: region) ?? region,
                                    dialCode: Int(dialCode),
                                    flag: PhoneNumbers.flag(region))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    /// A two-letter region PhoneNumberKit has metadata for. Leaves out "001", its
    /// code for non-geographic numbering plans, and Locale regions such as "419".
    private nonisolated static func isCountryCode(_ region: String) -> Bool {
        region.count == 2
            && region.allSatisfy { character in character.isASCII && character.isUppercase }
            && utility.countryCode(for: region) != nil
    }

    /// Parsed and valid under `region`, or nil. PhoneNumberKit rejects an unknown
    /// region before it looks for a leading "+", so an international number is
    /// parsed under a known one instead (the "+" makes the region irrelevant).
    private nonisolated static func parse(_ input: String, region: String) -> PhoneNumber? {
        let known = utility.countryCode(for: region) != nil
        let international = input.hasPrefix("+") || input.hasPrefix("＋")
        guard known || international else { return nil }
        return try? utility.parse(input, withRegion: known ? region : "US", ignoreType: false)
    }

    /// Mexico's retired dialing forms, which PhoneNumberKit's metadata no longer
    /// accepts: the mobile "1" after the country code (+52 1 55 1234 5678) and the
    /// 044/045 mobile prefixes in front of a national number (044 55 1234 5678).
    /// Returns "+52" plus the ten-digit number, or nil when neither form applies.
    private nonisolated static func mexicanRewrite(digits: String, hasPlus: Bool, defaultRegion: String) -> String? {
        guard digits.count == 13 else { return nil }
        let isMexico = defaultRegion.uppercased() == "MX"
        if digits.hasPrefix("521"), hasPlus || isMexico {
            return "+52" + String(digits.suffix(10))
        }
        if !hasPlus, isMexico, digits.hasPrefix("044") || digits.hasPrefix("045") {
            return "+52" + String(digits.suffix(10))
        }
        return nil
    }

    private nonisolated static func asciiDigits(_ text: String) -> String {
        text.filter { character in character.isASCII && character.isWholeNumber }
    }

    /// Drops invisible formatting characters (Unicode category Cf), such as the
    /// direction marks that wrap numbers copied from chat apps.
    private nonisolated static func withoutFormatCharacters(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .format
        })
        return String(scalars)
    }

    /// The flag emoji for a two-letter region: each letter becomes its regional
    /// indicator symbol, and the pair renders as the flag.
    private nonisolated static func flag(_ region: String) -> String {
        var scalars = String.UnicodeScalarView()
        for letter in region.uppercased().unicodeScalars {
            guard let indicator = Unicode.Scalar(0x1F1E6 - 0x41 + letter.value) else { return "" }
            scalars.append(indicator)
        }
        return String(scalars)
    }
}
