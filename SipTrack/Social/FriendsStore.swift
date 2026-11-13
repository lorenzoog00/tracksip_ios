import Foundation
import UIKit
import Combine
import FirebaseFirestore

enum ReportKind: String {
    case username
    case photo
}

/// Everything the Friends tab shows: my profile, friends, requests, blocks and the feed.
/// Reads go straight to Firestore (rules allow exactly these shapes); writes go through
/// the server callables in `FirebaseManager`.
@MainActor
final class FriendsStore: ObservableObject {
    @Published private(set) var myProfile: FriendProfile?
    @Published private(set) var friends: [FriendProfile] = []
    @Published private(set) var incoming: [FriendProfile] = []
    @Published private(set) var outgoing: [FriendProfile] = []
    @Published private(set) var blocked: [FriendProfile] = []
    @Published private(set) var feed: [FeedItem] = []
    /// True once the first `public_profiles` snapshot has arrived (even for a missing doc),
    /// so `myProfile == nil` can be told apart from "not loaded yet".
    @Published private(set) var profileLoaded = false

    var liveCount: Int {
        let now = Date()
        return feed.filter { $0.night.isLive(now: now) }.count
    }

    var pendingCount: Int { incoming.count }

    private weak var appState: AppState?
    private var uid: String?
    /// Bumped by every start/stop so a late Firestore callback from an old account is dropped.
    private var session = 0

    private var listeners: [ListenerRegistration] = []
    private var nightListeners: [String: ListenerRegistration] = [:]
    private var nights: [String: SharedNight] = [:]
    /// Per-friend back-off for night listeners the server denied (expired, not yet TTL-deleted).
    private var nightRetries: [String: Task<Void, Never>] = [:]
    private var nightFailures: [String: Int] = [:]
    private static let retryDelays: [UInt64] = [120, 300, 900]

    private var friendUids: [String] = []
    private var incomingUids: [String] = []
    private var outgoingUids: [String] = []
    private var blockedUids: [String] = []

    private var profiles: [String: FriendProfile] = [:]
    private var resolving: Set<String> = []

    /// Ask for push permission once per signed-in session, when the first request shows up.
    private var askedPushForIncoming = false
    private var authCancellable: AnyCancellable?
    private var foregroundCancellable: AnyCancellable?

    private var db: Firestore { Firestore.firestore() }

    init(appState: AppState) {
        self.appState = appState
        authCancellable = FirebaseManager.shared.$isSignedIn
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] signedIn in
                guard let self else { return }
                if signedIn, let uid = FirebaseManager.shared.currentUserId() {
                    self.start(uid: uid)
                } else {
                    self.stop()
                }
            }
        foregroundCancellable = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.reattachDeadNightListeners() }
    }

    // MARK: - Lifecycle

    func start(uid: String) {
        if self.uid == uid { return }
        stop()
        self.uid = uid
        let s = session
        // Signed in: refresh the push token (never prompts).
        Task { await PushRegistration.registerIfAuthorized() }

        // includeMetadataChanges: a cache-only "missing" snapshot is skipped below, and the
        // server confirming it changes only metadata, which is not delivered otherwise.
        listeners.append(db.collection("public_profiles").document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                // An error or missing snapshot says nothing about the profile; ignore it.
                guard error == nil, let snap else { return }
                // At an offline cold start the cache can report "missing" for a profile
                // that exists; wait for the server before deciding there is no username.
                if !snap.exists && snap.metadata.isFromCache { return }
                let data = snap.data()
                Task { @MainActor [weak self] in
                    guard let self, self.session == s else { return }
                    let profile = data.flatMap { Self.profile(uid: uid, data: $0) }
                    self.applyMyProfile(profile, syncNight: true)
                    self.profileLoaded = true
                }
            })

        listeners.append(db.collection("friendships").document(uid).collection("friends")
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                let ids = snap.documents.map(\.documentID)
                Task { @MainActor [weak self] in
                    guard let self, self.session == s else { return }
                    self.friendUids = ids
                    self.syncNightListeners(session: s)
                    self.resolveProfiles(Set(ids), session: s)
                    self.rebuild()
                }
            })

        listeners.append(db.collection("friend_requests").whereField("to", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                let ids = snap.documents.compactMap { $0.data()["from"] as? String }
                Task { @MainActor [weak self] in
                    guard let self, self.session == s else { return }
                    self.incomingUids = ids
                    self.resolveProfiles(Set(ids), session: s)
                    self.rebuild()
                }
            })

        listeners.append(db.collection("friend_requests").whereField("from", isEqualTo: uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                let ids = snap.documents.compactMap { $0.data()["to"] as? String }
                Task { @MainActor [weak self] in
                    guard let self, self.session == s else { return }
                    self.outgoingUids = ids
                    self.resolveProfiles(Set(ids), session: s)
                    self.rebuild()
                }
            })

        listeners.append(db.collection("blocks").document(uid).collection("blocked")
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                let ids = snap.documents.map(\.documentID)
                Task { @MainActor [weak self] in
                    guard let self, self.session == s else { return }
                    self.blockedUids = ids
                    self.resolveProfiles(Set(ids), session: s)
                    self.rebuild()
                }
            })
    }

    /// Sign-out: remove every listener and clear all state.
    func stop() {
        session &+= 1
        listeners.forEach { $0.remove() }
        listeners = []
        nightListeners.values.forEach { $0.remove() }
        nightListeners = [:]
        nightRetries.values.forEach { $0.cancel() }
        nightRetries = [:]
        nightFailures = [:]
        nights = [:]
        friendUids = []
        incomingUids = []
        outgoingUids = []
        blockedUids = []
        profiles = [:]
        resolving = []
        uid = nil
        askedPushForIncoming = false
        // No night sync here: signed out, there is nothing to write or delete.
        applyMyProfile(nil, syncNight: false)
        profileLoaded = false
        friends = []
        incoming = []
        outgoing = []
        blocked = []
        feed = []
    }

    private func applyMyProfile(_ profile: FriendProfile?, syncNight: Bool) {
        if myProfile != profile { myProfile = profile }
        appState?.hasSocialProfile = (profile != nil)
        if syncNight { appState?.syncSharedNight() }
    }

    // MARK: - Profiles

    private func resolveProfiles(_ uids: Set<String>, session s: Int) {
        for id in uids where profiles[id] == nil && !resolving.contains(id) {
            resolving.insert(id)
            Task { [weak self] in
                let snap = try? await Firestore.firestore().collection("public_profiles").document(id).getDocument()
                let data = snap?.data()
                guard let self, self.session == s else { return }
                self.resolving.remove(id)
                if let data, let profile = Self.profile(uid: id, data: data) {
                    self.profiles[id] = profile
                    self.rebuild()
                }
            }
        }
    }

    private static func profile(uid: String, data: [String: Any]) -> FriendProfile? {
        guard let username = data["username"] as? String else { return nil }
        return FriendProfile(
            uid: uid,
            username: username,
            photoURL: (data["photo_url"] as? String).flatMap { URL(string: $0) },
            avatarColor: data["avatar_color"] as? String ?? ""
        )
    }

    private func rebuild() {
        func list(_ ids: [String]) -> [FriendProfile] {
            ids.compactMap { profiles[$0] }
                .sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        }
        friends = list(friendUids)
        incoming = list(incomingUids)
        outgoing = list(outgoingUids)
        blocked = list(blockedUids)
        if !incoming.isEmpty && !askedPushForIncoming {
            askedPushForIncoming = true
            let count = incoming.count
            Task { await PushRegistration.requestIfNeeded(incomingCount: count) }
        }
        feed = friends.compactMap { profile in
            nights[profile.uid].map { FeedItem(id: profile.uid, profile: profile, night: $0) }
        }
    }

    // MARK: - Friends' nights

    /// One listener per friend. A listener on a single doc is a `get`, which the rules allow;
    /// the collection cannot be queried.
    private func syncNightListeners(session s: Int) {
        let wanted = Set(friendUids)
        for (fid, listener) in nightListeners where !wanted.contains(fid) {
            listener.remove()
            nightListeners[fid] = nil
        }
        for fid in Array(nightRetries.keys) where !wanted.contains(fid) {
            nightRetries[fid]?.cancel()
            nightRetries[fid] = nil
        }
        for fid in Array(nightFailures.keys) where !wanted.contains(fid) {
            nightFailures[fid] = nil
        }
        for fid in nights.keys where !wanted.contains(fid) {
            nights[fid] = nil
        }
        for fid in wanted where nightListeners[fid] == nil && nightRetries[fid] == nil {
            attachNight(fid, session: s)
        }
    }

    private func attachNight(_ fid: String, session s: Int) {
        nightListeners[fid]?.remove()
        nightListeners[fid] = db.collection("shared_nights").document(fid)
            .addSnapshotListener { [weak self] snap, error in
                let failed = error != nil
                let data = failed ? nil : snap?.data()
                Task { @MainActor [weak self] in
                    guard let self, self.session == s, self.friendUids.contains(fid) else { return }
                    // Missing, unreadable (permission denied once expired or hidden) and
                    // expired all mean the same thing: nothing to show. No banner.
                    if !failed {
                        self.nightFailures[fid] = nil
                    }
                    if let data, let night = SharedNight(firestore: data), night.expiresAt > Date() {
                        self.nights[fid] = night
                    } else {
                        self.nights[fid] = nil
                    }
                    if failed {
                        // An errored listener is dead. Try again later so a new night shows up.
                        self.nightListeners[fid]?.remove()
                        self.nightListeners[fid] = nil
                        self.retryNight(fid, session: s)
                    }
                    self.rebuild()
                }
            }
    }

    /// One retry per friend, with growing delays. A friend with no night has a live listener
    /// (the rules allow a missing doc); a denial only means expired-but-not-yet-deleted.
    private func retryNight(_ fid: String, session s: Int) {
        guard nightRetries[fid] == nil else { return }
        let failures = (nightFailures[fid] ?? 0) + 1
        nightFailures[fid] = failures
        let delay = Self.retryDelays[min(failures - 1, Self.retryDelays.count - 1)]
        nightRetries[fid] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self, self.session == s else { return }
            self.nightRetries[fid] = nil
            guard self.friendUids.contains(fid), self.nightListeners[fid] == nil else { return }
            self.attachNight(fid, session: s)
        }
    }

    /// Back to the foreground: try every dead listener now instead of waiting out its back-off.
    private func reattachDeadNightListeners() {
        guard uid != nil else { return }
        let s = session
        nightRetries.values.forEach { $0.cancel() }
        nightRetries = [:]
        for fid in friendUids where nightListeners[fid] == nil {
            attachNight(fid, session: s)
        }
    }

    // MARK: - Actions (server callables)

    func claimUsername(_ name: String) async throws {
        try await FirebaseManager.shared.claimUsername(name)
    }

    func search(_ q: String) async throws -> [FriendProfile] {
        try await FirebaseManager.shared.searchUsers(query: q)
    }

    func sendRequest(to uid: String) async throws {
        try await FirebaseManager.shared.sendFriendRequest(toUid: uid)
        // Only reached on success: the first request sent is the moment to ask.
        Task { await PushRegistration.requestIfNeeded(sentCount: 1) }
    }

    func respond(to uid: String, accept: Bool) async throws {
        try await FirebaseManager.shared.respondToFriendRequest(fromUid: uid, accept: accept)
    }

    func cancelRequest(to uid: String) async throws {
        try await FirebaseManager.shared.cancelFriendRequest(toUid: uid)
    }

    func remove(_ uid: String) async throws {
        try await FirebaseManager.shared.removeFriend(friendUid: uid)
    }

    func block(_ uid: String) async throws {
        try await FirebaseManager.shared.blockUser(targetUid: uid)
    }

    func unblock(_ uid: String) async throws {
        try await FirebaseManager.shared.unblockUser(targetUid: uid)
    }

    func report(_ uid: String, kind: ReportKind) async throws {
        try await FirebaseManager.shared.reportUser(targetUid: uid, kind: kind.rawValue)
    }

    /// nil removes the photo.
    func setAvatar(_ image: UIImage?) async throws {
        var payload: Any = NSNull()
        if let image {
            let size = CGSize(width: 256, height: 256)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                // Aspect-fill so a non-square photo is cropped, not squashed.
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let w = image.size.width * scale
                let h = image.size.height * scale
                image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
            }
            guard let jpeg = resized.jpegData(compressionQuality: 0.7) else {
                throw NSError(domain: "FriendsStore", code: 400,
                              userInfo: [NSLocalizedDescriptionKey: "That photo could not be used."])
            }
            payload = jpeg.base64EncodedString()
        }
        try await FirebaseManager.shared.setAvatar(jpegBase64: payload)
    }
}
