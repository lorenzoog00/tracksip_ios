import Foundation
import FirebaseFirestore

/// The two reactions: a beer (cheers) or a water (have some water). Stored and sent
/// by key (`rawValue`), never by emoji. Older keys (fire, laugh, woozy, heart) can
/// still be in a summary's counts; they don't parse and are ignored.
nonisolated enum Reaction: String, CaseIterable, Identifiable {
    case beer, water

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .beer: return "🍻"
        case .water: return "💧"
        }
    }
}

/// One shared night: `{owner}_{startedAtMs}`, the id of its `night_threads` doc.
/// Identifiable so the comment sheet can be presented with `.sheet(item:)`.
nonisolated struct NightKey: Hashable, Identifiable {
    let owner: String
    /// The shared night's start in ms.
    let startedAt: Int64

    var id: String { "\(owner)_\(startedAt)" }

    init(owner: String, startedAt: Int64) {
        self.owner = owner
        self.startedAt = startedAt
    }

    /// Rounded exactly like `SharedNight` writes `started_at`.
    init(owner: String, night: SharedNight) {
        self.init(owner: owner, startedAt: night.startedAtMs)
    }
}

nonisolated struct ThreadMention: Equatable, Hashable {
    var uid: String
    var username: String
}

nonisolated struct ThreadComment: Identifiable, Equatable {
    var id: String
    var uid: String
    var username: String
    var text: String
    var mentions: [ThreadMention]
    var at: Date
    /// Sent but not yet confirmed by the server.
    var isPending: Bool = false

    init(id: String, uid: String, username: String, text: String,
         mentions: [ThreadMention], at: Date, isPending: Bool = false) {
        self.id = id
        self.uid = uid
        self.username = username
        self.text = text
        self.mentions = mentions
        self.at = at
        self.isPending = isPending
    }

    /// A comment row from Firestore or a callable. `uid` and `username` may be
    /// absent (addComment returns neither); they fall back to the given values.
    static func parse(_ row: [String: Any], uid fallbackUid: String = "",
                      username fallbackUsername: String = "") -> ThreadComment? {
        guard let id = row["id"] as? String, let text = row["text"] as? String else { return nil }
        let mentions = (row["mentions"] as? [Any] ?? []).compactMap { raw -> ThreadMention? in
            guard let dict = raw as? [String: Any],
                  let uid = dict["uid"] as? String,
                  let username = dict["username"] as? String
            else { return nil }
            return ThreadMention(uid: uid, username: username)
        }
        return ThreadComment(
            id: id,
            uid: row["uid"] as? String ?? fallbackUid,
            username: row["username"] as? String ?? fallbackUsername,
            text: text,
            mentions: mentions,
            at: ThreadValue.date(row["at"]) ?? Date()
        )
    }
}

/// The `night_threads/{key}` summary doc. A missing doc is an empty summary.
nonisolated struct ThreadSummary: Equatable {
    var counts: [Reaction: Int] = [:]
    var reactors: [String] = []
    var commentCount: Int = 0
    var latest: [ThreadComment] = []

    /// The comment count without people I blocked, when the summary can tell: with
    /// nobody blocked, or when every comment is among `latest`. Otherwise nil (a
    /// blocked person may have written comments the summary doesn't carry), and
    /// the card shows no number; the sheet counts what it loaded.
    func visibleCommentCount(blocked: Set<String>) -> Int? {
        if blocked.isEmpty { return commentCount }
        guard commentCount <= latest.count else { return nil }
        return latest.filter { !blocked.contains($0.uid) }.count
    }

    /// Missing fields read as zero; unknown reaction keys and zero counts are dropped.
    static func parse(_ data: [String: Any]) -> ThreadSummary? {
        var summary = ThreadSummary()
        if let raw = data["reactions"] as? [String: Any] {
            for (key, value) in raw {
                guard let reaction = Reaction(rawValue: key),
                      let count = ThreadValue.number(value).map({ Int($0) }),
                      count > 0
                else { continue }
                summary.counts[reaction] = count
            }
        }
        summary.reactors = (data["reactors"] as? [Any] ?? []).compactMap { $0 as? String }
        summary.commentCount = max(0, ThreadValue.number(data["comment_count"]).map { Int($0) } ?? 0)
        summary.latest = (data["latest_comments"] as? [Any] ?? []).compactMap { raw in
            (raw as? [String: Any]).flatMap { ThreadComment.parse($0) }
        }
        return summary
    }
}

nonisolated enum ReactionMath {
    /// Counts after one person's reaction goes from `old` to `new`.
    /// Never negative; zero entries are removed.
    static func apply(counts: [Reaction: Int], old: Reaction?, new: Reaction?) -> [Reaction: Int] {
        var result = counts
        if let old { result[old] = (result[old] ?? 0) - 1 }
        if let new { result[new] = max(0, result[new] ?? 0) + 1 }
        return result.filter { $0.value > 0 }
    }
}

nonisolated enum MentionText {
    /// Characters a username can hold.
    static func isNameCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "." || c == "_"
    }

    /// The name being typed after an `@` that ends at `cursor` (a character offset),
    /// or nil when the cursor is not in a mention. "hey @bo" → "bo", "@" → "".
    /// The `@` must start the text or follow whitespace, so "a@b" is not a mention.
    static func activeQuery(in text: String, cursor: Int) -> String? {
        let chars = Array(text)
        var i = min(max(0, cursor), chars.count) - 1
        var name: [Character] = []
        while i >= 0 {
            let c = chars[i]
            if c == "@" {
                guard i == 0 || chars[i - 1].isWhitespace else { return nil }
                return String(name.reversed())
            }
            guard isNameCharacter(c) else { return nil }
            name.append(c)
            i -= 1
        }
        return nil
    }

    /// Splits `text` into runs, flagging `@name` runs whose name is in `mentions`
    /// (case-insensitive). Any other `@name` stays plain text.
    static func segments(_ text: String, mentions: [ThreadMention]) -> [(String, Bool)] {
        let names = Set(mentions.map { $0.username.lowercased() })
        let chars = Array(text)
        var result: [(String, Bool)] = []
        var plain = ""
        var i = 0

        func flushPlain() {
            if !plain.isEmpty {
                result.append((plain, false))
                plain = ""
            }
        }

        while i < chars.count {
            if chars[i] == "@", i == 0 || chars[i - 1].isWhitespace, !names.isEmpty {
                var end = i + 1
                while end < chars.count, isNameCharacter(chars[end]) { end += 1 }
                // A sentence-ending "." is not part of the name.
                while end > i + 1, chars[end - 1] == ".",
                      !names.contains(String(chars[(i + 1)..<end]).lowercased()) {
                    end -= 1
                }
                let name = String(chars[(i + 1)..<end])
                if !name.isEmpty, names.contains(name.lowercased()) {
                    flushPlain()
                    result.append(("@" + name, true))
                    i = end
                    continue
                }
            }
            plain.append(chars[i])
            i += 1
        }
        flushPlain()
        return result
    }
}

/// Firestore and callables hand numbers back as Int, Int64, Double or NSNumber.
nonisolated enum ThreadValue {
    static func number(_ value: Any?) -> Double? {
        switch value {
        case let v as Double: return v
        case let v as Int: return Double(v)
        case let v as Int64: return Double(v)
        case let v as NSNumber: return v.doubleValue
        default: return nil
        }
    }

    /// ms since 1970, or a Firestore Timestamp.
    static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return number(value).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}
