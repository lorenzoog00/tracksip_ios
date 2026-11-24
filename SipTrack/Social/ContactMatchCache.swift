//
//  ContactMatchCache.swift
//  SipTrack
//
//  The last contacts check, kept on this phone per account for 24 hours, so
//  reopening the app or the screen shows it again instead of spending one of
//  the server's two checks a day. Only the answer is kept: the matched Social
//  profiles and the matched numbers, never the address book.
//

import Foundation

/// A matched person as saved on the phone: a Codable mirror of `FriendProfile`.
nonisolated struct FriendProfileSnapshot: Codable, Equatable, Sendable {
    var uid: String
    var username: String
    var photoURL: URL?
    var avatarColor: String
    /// Missing from checks saved before display names; those decode with nil.
    var name: String? = nil
}

extension FriendProfileSnapshot {
    @MainActor init(_ profile: FriendProfile) {
        self.init(uid: profile.uid, username: profile.username,
                  photoURL: profile.photoURL, avatarColor: profile.avatarColor, name: profile.name)
    }

    @MainActor var profile: FriendProfile {
        FriendProfile(uid: uid, username: username, photoURL: photoURL, avatarColor: avatarColor, name: name)
    }
}

/// What `matchContacts` answered: the contacts on TrackSip Social, and every
/// matched number (E.164), so the Invite list can leave those people out.
nonisolated struct ContactMatchResult: Codable, Equatable, Sendable {
    var profiles: [FriendProfileSnapshot]
    var onTrackSip: Set<String>
}

nonisolated struct ContactMatchCache: Codable, Equatable, Sendable {
    var result: ContactMatchResult
    var checkedAt: Date
    /// The account's number when the check ran. A changed or removed number
    /// makes the result stale: who can be found depends on it.
    var ownerPhone: String

    /// The server's rolling window for its two checks.
    static let validFor: TimeInterval = 24 * 3600

    /// True for a check under 24 hours old, made with the number the account
    /// has now.
    static func isFresh(_ cache: ContactMatchCache?, now: Date, currentPhone: String?) -> Bool {
        guard let cache, let currentPhone, cache.ownerPhone == currentPhone else { return false }
        let age = now.timeIntervalSince(cache.checkedAt)
        return age >= 0 && age < validFor
    }

    /// The saved check, unless it is 24 hours old or more: that one can never
    /// be fresh again, so it is removed from the phone instead of lingering.
    static func load(uid: String, now: Date = Date()) -> ContactMatchCache? {
        guard let data = UserDefaults.standard.data(forKey: key(uid)),
              let cache = try? JSONDecoder().decode(ContactMatchCache.self, from: data) else { return nil }
        if now.timeIntervalSince(cache.checkedAt) >= validFor {
            clear(uid: uid)
            return nil
        }
        return cache
    }

    static func save(_ cache: ContactMatchCache, uid: String) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key(uid))
    }

    static func clear(uid: String) {
        UserDefaults.standard.removeObject(forKey: key(uid))
    }

    private static func key(_ uid: String) -> String {
        "contactMatch.\(uid)"
    }
}
