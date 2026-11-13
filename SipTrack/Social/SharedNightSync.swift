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
    ///   - event: the night being shared (nil when there is none).
    ///   - night: the freshly built shared night for `event`.
    ///   - lastSent: what was last written successfully this session.
    ///   - hasUsername: false until the user has a social profile; nothing is shared before that.
    static func action(
        event: NightEvent?,
        night: SharedNight?,
        lastSent: SharedNight?,
        hasUsername: Bool
    ) -> SharedNightAction {
        guard hasUsername, let event else { return .none }
        // Incognito always deletes: `lastSent` is nil after a relaunch even though a
        // night may still be on the server, so it cannot be trusted to skip the delete.
        if event.isIncognito { return .delete }
        guard let night else { return .none }
        if night == lastSent { return .none }
        return .write(night)
    }
}
