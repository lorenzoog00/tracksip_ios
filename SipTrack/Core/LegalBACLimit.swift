import Foundation

// Statutory general-driver drink-drive BAC limit (BAC %) by ISO-3166 alpha-2
// country code. Where a country has multiple sub-jurisdictions (UK Scotland
// 0.05 vs Eng/Wales/NI 0.08, US Utah 0.05 vs other states 0.08) we list the
// most common / federal value and note it.
//
// Sources: WHO BAC limits indicator, Wikipedia "Drunk driving law by country"
// (cross-checked May 2026), IARD, drinkdriving.org. See
// .planning/research/BAC-ACCURACY-RESEARCH.md §11.
struct LegalBACLimit: Identifiable, Equatable {
    let countryCode: String   // ISO-3166 alpha-2, uppercased
    let name: String
    let general: Double
    let novice: Double
    let commercial: Double
    let note: String?

    var id: String { countryCode }

    var flagEmoji: String {
        countryCode.unicodeScalars.compactMap { s -> String? in
            guard s.value >= 65, s.value <= 90 else { return nil }
            return UnicodeScalar(127397 + s.value).map { String($0) }
        }.joined()
    }

    func limit(for driver: DriverType) -> Double {
        switch driver {
        case .general:    return general
        case .novice:     return novice
        case .commercial: return commercial
        }
    }
}

enum LegalBACLimits {

    // ~55 jurisdictions covering >90% of the SipTrack user base. Ordered
    // alphabetically by display name for the picker.
    static let all: [LegalBACLimit] = [
        .init(countryCode: "AR", name: "Argentina",       general: 0.05, novice: 0.02, commercial: 0.00, note: nil),
        .init(countryCode: "AU", name: "Australia",       general: 0.05, novice: 0.00, commercial: 0.00, note: "Zero for L/P plates & heavy vehicles"),
        .init(countryCode: "AT", name: "Austria",         general: 0.05, novice: 0.01, commercial: 0.01, note: nil),
        .init(countryCode: "BE", name: "Belgium",         general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "BR", name: "Brazil",          general: 0.02, novice: 0.00, commercial: 0.00, note: "Effectively zero (lab tolerance only)"),
        .init(countryCode: "CA", name: "Canada",          general: 0.08, novice: 0.00, commercial: 0.04, note: "Federal criminal 0.08; provincial admin 0.05"),
        .init(countryCode: "CL", name: "Chile",           general: 0.03, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "CN", name: "China",           general: 0.02, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "CO", name: "Colombia",        general: 0.04, novice: 0.04, commercial: 0.00, note: nil),
        .init(countryCode: "CZ", name: "Czech Republic",  general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "DK", name: "Denmark",         general: 0.05, novice: 0.02, commercial: 0.05, note: "Novice 0.02 from July 2025"),
        .init(countryCode: "EG", name: "Egypt",           general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "EE", name: "Estonia",         general: 0.02, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "FI", name: "Finland",         general: 0.05, novice: 0.05, commercial: 0.00, note: nil),
        .init(countryCode: "FR", name: "France",          general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "DE", name: "Germany",         general: 0.05, novice: 0.00, commercial: 0.00, note: "Zero for under-21 & first 2 years"),
        .init(countryCode: "GR", name: "Greece",          general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "HU", name: "Hungary",         general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "IS", name: "Iceland",         general: 0.05, novice: 0.05, commercial: 0.00, note: nil),
        .init(countryCode: "IN", name: "India",           general: 0.03, novice: 0.03, commercial: 0.00, note: nil),
        .init(countryCode: "ID", name: "Indonesia",       general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "IE", name: "Ireland",         general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "IL", name: "Israel",          general: 0.024, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "IT", name: "Italy",           general: 0.05, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "JP", name: "Japan",           general: 0.03, novice: 0.03, commercial: 0.03, note: nil),
        .init(countryCode: "KE", name: "Kenya",           general: 0.08, novice: 0.08, commercial: 0.08, note: nil),
        .init(countryCode: "KR", name: "South Korea",     general: 0.03, novice: 0.03, commercial: 0.03, note: nil),
        .init(countryCode: "MX", name: "Mexico",          general: 0.08, novice: 0.08, commercial: 0.04, note: nil),
        .init(countryCode: "MY", name: "Malaysia",        general: 0.08, novice: 0.08, commercial: 0.08, note: nil),
        .init(countryCode: "NL", name: "Netherlands",     general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "NZ", name: "New Zealand",     general: 0.05, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "NG", name: "Nigeria",         general: 0.05, novice: 0.05, commercial: 0.05, note: nil),
        .init(countryCode: "NO", name: "Norway",          general: 0.02, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "PE", name: "Peru",            general: 0.05, novice: 0.05, commercial: 0.00, note: nil),
        .init(countryCode: "PH", name: "Philippines",     general: 0.05, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "PL", name: "Poland",          general: 0.02, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "PT", name: "Portugal",        general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "RO", name: "Romania",         general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "RU", name: "Russia",          general: 0.016, novice: 0.016, commercial: 0.016, note: "Lab tolerance only — effectively zero"),
        .init(countryCode: "SA", name: "Saudi Arabia",    general: 0.00, novice: 0.00, commercial: 0.00, note: "Alcohol prohibited"),
        .init(countryCode: "RS", name: "Serbia",          general: 0.02, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "SG", name: "Singapore",       general: 0.08, novice: 0.08, commercial: 0.08, note: nil),
        .init(countryCode: "SK", name: "Slovakia",        general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "ZA", name: "South Africa",    general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "ES", name: "Spain",           general: 0.05, novice: 0.03, commercial: 0.03, note: nil),
        .init(countryCode: "SE", name: "Sweden",          general: 0.02, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "CH", name: "Switzerland",     general: 0.05, novice: 0.01, commercial: 0.01, note: nil),
        .init(countryCode: "TH", name: "Thailand",        general: 0.05, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "TR", name: "Türkiye",         general: 0.05, novice: 0.00, commercial: 0.00, note: nil),
        .init(countryCode: "UA", name: "Ukraine",         general: 0.02, novice: 0.02, commercial: 0.02, note: nil),
        .init(countryCode: "AE", name: "United Arab Emirates", general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "GB", name: "United Kingdom",  general: 0.08, novice: 0.08, commercial: 0.08, note: "Scotland 0.05; rest 0.08"),
        .init(countryCode: "US", name: "United States",   general: 0.08, novice: 0.02, commercial: 0.04, note: "Utah 0.05; under-21 zero tolerance"),
        .init(countryCode: "UY", name: "Uruguay",         general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
        .init(countryCode: "VN", name: "Vietnam",         general: 0.00, novice: 0.00, commercial: 0.00, note: "Zero tolerance"),
    ]

    static func find(_ countryCode: String?) -> LegalBACLimit? {
        guard let cc = countryCode?.uppercased() else { return nil }
        return all.first { $0.countryCode == cc }
    }

    // First-launch detection. Reads Locale.current.region with a fallback to
    // the older regionCode API. Returns the matched LegalBACLimit if we have
    // an entry for that country, else nil.
    static func detectFromLocale() -> LegalBACLimit? {
        let code: String?
        if #available(iOS 16, *) {
            code = Locale.current.region?.identifier
        } else {
            code = Locale.current.regionCode
        }
        return find(code)
    }
}

extension UserProfile {
    var legalBACLimit: LegalBACLimit? { LegalBACLimits.find(countryCode) }
    var resolvedBACLimit: Double { legalBACLimit?.limit(for: driverType) ?? bacLimit }
}
