import Foundation

/// The public "add me" link: `https://looqs.online/siptrack/u/<username>`, or the
/// `siptrack://u/<username>` form the web fallback page opens the app with.
enum FriendLink {
    private static let host = "looqs.online"

    nonisolated static func isValid(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard (3...20).contains(scalars.count) else { return false }
        return scalars.allSatisfy { s in
            (s.value >= 97 && s.value <= 122) || (s.value >= 48 && s.value <= 57) || s == "." || s == "_"
        }
    }

    /// The lowercased username in a friend link, or nil for any other URL.
    nonisolated static func username(from url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let raw: String
        switch url.scheme?.lowercased() {
        case "https":
            guard url.host?.lowercased() == host,
                  parts.count == 3, parts[0].lowercased() == "siptrack", parts[1].lowercased() == "u"
            else { return nil }
            raw = parts[2]
        case "siptrack":
            guard url.host?.lowercased() == "u", parts.count == 1 else { return nil }
            raw = parts[0]
        default:
            return nil
        }
        let name = raw.lowercased()
        return isValid(name) ? name : nil
    }

    nonisolated static func shareURL(for username: String) -> URL {
        URL(string: "https://\(host)/siptrack/u/\(username)") ?? URL(string: "https://\(host)/siptrack")!
    }
}
