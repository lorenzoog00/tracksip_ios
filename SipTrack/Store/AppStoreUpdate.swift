import Foundation
import StoreKit

struct AppStoreUpdate: Equatable {
    let version: String

    private static let appID = 6_762_666_633
    static let productURL = URL(string: "https://apps.apple.com/app/id\(appID)")!

    static func check() async throws -> Self? {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }

        let storefront = await Storefront.current
        guard let country = storefront.flatMap({ lookupCountryCode($0.countryCode) })
                ?? Locale.current.region.flatMap({ lookupCountryCode($0.identifier) })
        else { return nil }

        var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
        lookup.queryItems = [
            URLQueryItem(name: "id", value: String(appID)),
            URLQueryItem(name: "country", value: country)
        ]
        let request = URLRequest(url: lookup.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return try available(in: data, bundleID: bundleID, installedVersion: installedVersion, systemVersion: systemVersion)
    }

    static func lookupCountryCode(_ code: String) -> String? {
        // StoreKit supplies alpha-3 codes. Lookup takes the canonical alpha-2 region.
        let identifier = Locale.canonicalIdentifier(from: "en_\(code)")
        guard let region = Locale(identifier: identifier).region?.identifier,
              region.utf8.count == 2,
              region.utf8.allSatisfy({ (65...90).contains($0) })
        else { return nil }
        return region.lowercased()
    }

    static func available(
        in data: Data, bundleID: String, installedVersion: String, systemVersion: String
    ) throws -> Self? {
        let response = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let app = response.results.first(where: { $0.trackId == appID && $0.bundleId == bundleID }),
              compare(app.version, installedVersion) == .orderedDescending
        else { return nil }

        if let minimum = app.minimumOsVersion {
            guard let compatibility = compare(systemVersion, minimum), compatibility != .orderedAscending else {
                return nil
            }
        }
        return Self(version: app.version)
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        func components(of version: String) -> [Int]? {
            let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
            let numbers = pieces.compactMap { Int($0) }
            guard !pieces.isEmpty, numbers.count == pieces.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
            return numbers
        }
        guard let left = components(of: lhs), let right = components(of: rhs) else { return nil }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private struct LookupResponse: Decodable {
        let results: [Listing]

        struct Listing: Decodable {
            let trackId: Int
            let bundleId: String
            let version: String
            let minimumOsVersion: String?
        }
    }
}
