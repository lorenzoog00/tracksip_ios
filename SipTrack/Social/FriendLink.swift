import Foundation

/// The public "add me" link: `https://tracksip.online/u/<username>`, or the
/// `siptrack://u/<username>` form the web fallback page opens the app with.
/// Older builds shared `https://looqs.online/siptrack/u/<username>`; those still open.
enum FriendLink {
    private nonisolated static let host = "tracksip.online"
    private nonisolated static let legacyHost = "looqs.online"

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
            switch url.host?.lowercased() {
            case host, "www." + host:
                guard parts.count == 2, parts[0].lowercased() == "u" else { return nil }
                raw = parts[1]
            case legacyHost:
                guard parts.count == 3, parts[0].lowercased() == "siptrack", parts[1].lowercased() == "u"
                else { return nil }
                raw = parts[2]
            default:
                return nil
            }
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
        URL(string: "https://\(host)/u/\(username)") ?? URL(string: "https://\(host)")!
    }
}
