import Foundation

struct FriendProfile: Equatable {
    var uid: String
    var username: String
    var photoURL: URL?
    var avatarColor: String
}

/// Someone "You might know", with why: shared friends or your contacts.
struct PersonSuggestion: Equatable, Identifiable {
    enum Reason: Equatable {
        /// `via` is one of the shared friends, nil if their profile is gone.
        case mutualFriends(count: Int, via: String?)
        case contact
    }

    var profile: FriendProfile
    var reason: Reason
    var id: String { profile.uid }

    /// The grey line under the username.
    var subtitle: String {
        switch reason {
        case .contact:
            return "In your contacts"
        case .mutualFriends(let count, let via):
            guard let via else { return count == 1 ? "1 friend in common" : "\(count) friends in common" }
            switch count {
            case ..<2: return "Friends with @\(via)"
            case 2: return "Friends with @\(via) and 1 other"
            default: return "Friends with @\(via) and \(count - 1) others"
            }
        }
    }
}

struct FeedItem: Identifiable {
    /// Friend uid.
    var id: String
    var profile: FriendProfile
    var night: SharedNight
}

enum FeedOrdering {
    /// Drops expired nights. Live (open) nights first by most recent drink; finished
    /// nights by most recent end.
    static func sections(_ items: [FeedItem], now: Date) -> (live: [FeedItem], recent: [FeedItem]) {
        let unexpired = items.filter { $0.night.expiresAt > now }
        let live = unexpired
            .filter { $0.night.isLive(now: now) }
            .sorted { $0.night.lastDrinkAt > $1.night.lastDrinkAt }
        let recent = unexpired
            .filter { $0.night.endedAt != nil }
            .sorted { ($0.night.endedAt ?? .distantPast) > ($1.night.endedAt ?? .distantPast) }
        return (live, recent)
    }
}
