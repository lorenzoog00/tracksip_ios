import Foundation

/// What to do with the shared night in Firestore after a change.
nonisolated enum SharedNightAction: Equatable {
    case write(SharedNight)
    case delete
    case none
}

/// Pure decision logic for syncing the shared night. Privacy: an incognito night
/// can never produce `.write`.
nonisolated enum SharedNightSync {
    /// - Parameters:
    ///   - isIncognito: the shared event's incognito flag; nil when there is no event.
    ///     Plain values only, so this stays free of the MainActor-isolated NightEvent.
    ///   - night: the freshly built shared night for the event.
    ///   - lastSent: what was last written successfully this session.
    ///   - hasUsername: false until the user has a social profile; nothing is written before that.
    static func action(
        isIncognito: Bool?,
        night: SharedNight?,
        lastSent: SharedNight?,
        hasUsername: Bool
    ) -> SharedNightAction {
        guard let isIncognito else { return .none }
        // Incognito always deletes, with or without a username: `lastSent` is nil after
        // a relaunch even though a night may still be on the server.
        if isIncognito { return .delete }
        guard hasUsername, let night else { return .none }
        if night == lastSent { return .none }
        return .write(night)
    }
}
