import Foundation

struct FriendProfile: Equatable {
    var uid: String
    var username: String
    var photoURL: URL?
    var avatarColor: String
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
