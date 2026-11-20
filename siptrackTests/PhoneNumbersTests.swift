//
//  PhoneNumbersTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct PhoneNumbersTests {
    @Test func mexicanFormsAllNormalizeToTheSameNumber() {
        for raw in ["55 1234 5678", "5512345678", "+52 55 1234 5678", "+52 1 55 1234 5678",
                    "044 55 1234 5678", "045 55 1234 5678", "(55) 1234-5678", "+521 5512345678",
                    "00 52 55 1234 5678", "00 52 1 55 1234 5678", "011 52 55 1234 5678",
                    "011 52 1 55 1234 5678", "01 55 1234 5678"] {
            #expect(PhoneNumbers.normalize(raw, defaultRegion: "MX") == "+525512345678", "\(raw)")
        }
    }

    @Test func internationalPrefixDialingMexicoNormalizesInAnyRegion() {
        for raw in ["00 52 55 1234 5678", "00 52 1 55 1234 5678", "011 52 55 1234 5678",
                    "011 52 1 55 1234 5678"] {
            #expect(PhoneNumbers.normalize(raw, defaultRegion: "US") == "+525512345678", "\(raw)")
        }
    }

    @Test func internationalPrefixDialingAnotherCountryIsLeftToPhoneNumberKit() {
        // 011 is the US international prefix and 00 Mexico's; only 52 after them is rewritten.
        #expect(PhoneNumbers.normalize("011 1 415 555 2671", defaultRegion: "US") == "+14155552671")
        #expect(PhoneNumbers.normalize("00 1 415 555 2671", defaultRegion: "MX") == "+14155552671")
    }

    @Test func usNumbersNormalize() {
        #expect(PhoneNumbers.normalize("(415) 555-2671", defaultRegion: "US") == "+14155552671")
        #expect(PhoneNumbers.normalize("+1 415 555 2671", defaultRegion: "MX") == "+14155552671")
    }

    @Test func nationalNumberUsesTheUsersRegionOrIsDropped() {
        // A US user with a Monterrey friend saved without +52: read as US, invalid there → nil.
        #expect(PhoneNumbers.normalize("81 1234 5678", defaultRegion: "US") == nil)
        #expect(PhoneNumbers.normalize("81 1234 5678", defaultRegion: "MX") == "+528112345678")
        // Read as US even when it happens to be valid there: 551 is a New Jersey area code.
        #expect(PhoneNumbers.normalize("55 1234 5678", defaultRegion: "US") == "+15512345678")
    }

    @Test func junkIsDropped() {
        for raw in ["", "abc", "123", "+", "++52551234", String(repeating: "9", count: 40)] {
            #expect(PhoneNumbers.normalize(raw, defaultRegion: "MX") == nil, "\(raw)")
        }
    }

    @Test func invisibleDirectionMarksAreIgnored() {
        // Numbers pasted from WhatsApp often arrive wrapped in U+202A … U+202C.
        #expect(PhoneNumbers.normalize("\u{202A}+52 55 1234 5678\u{202C}", defaultRegion: "US") == "+525512345678")
    }

    @Test func e164FromNationalChecksTheCountry() {
        #expect(PhoneNumbers.e164(national: "5512345678", region: "MX") == "+525512345678")
        #expect(PhoneNumbers.e164(national: "01 55 1234 5678", region: "MX") == "+525512345678")
        #expect(PhoneNumbers.e164(national: "551234567", region: "MX") == nil)   // 9 digits
    }

    @Test func regionOfE164() {
        #expect(PhoneNumbers.region(ofE164: "+525512345678") == "MX")
        #expect(PhoneNumbers.region(ofE164: "+14155552671") == "US")
    }

    @Test func formattedIsInternational() {
        #expect(PhoneNumbers.formatted("+525512345678") == "+52 55 1234 5678")
        #expect(PhoneNumbers.formatted("not a number") == "not a number")
    }

    @Test func formattedPartialFormatsACompleteNationalNumber() {
        #expect(PhoneNumbers.formattedPartial("5512345678", region: "MX") == "55 1234 5678")
    }

    @Test func countriesIncludeMexicoWithFlagAndDialCode() {
        let mx = PhoneNumbers.countries.first { $0.region == "MX" }
        #expect(mx?.dialCode == 52)
        #expect(mx?.flag == "🇲🇽")
    }

    @Test func countriesAreRealRegionsOnly() {
        let regions = PhoneNumbers.countries.map(\.region)
        #expect(!regions.contains("001"))   // PhoneNumberKit's non-geographic numbering plans
        #expect(Set(regions).count == regions.count)
    }
}
