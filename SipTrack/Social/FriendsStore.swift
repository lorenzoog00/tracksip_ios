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
    /// Friends' nights, one item per night: a friend's live night and the ended one
    /// before it both show.
    @Published private(set) var feed: [FeedItem] = []
    /// My own shared nights (the main doc and my unexpired ended copies, one item per
    /// night), shown on top of the feed as "You". Empty while there are none or they
    /// are unreadable (incognito nights are never written).
    @Published private(set) var myNights: [FeedItem] = []
    /// True once the first `public_profiles` snapshot has arrived (even for a missing doc),
    /// so `myProfile == nil` can be told apart from "not loaded yet".
    @Published private(set) var profileLoaded = false
    /// Friend actions shown on the rows before the server and the listeners
    /// confirm them; read through `rowState(for:)`.
    @Published private(set) var pending = PendingFriendActions()

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
    private var myNightListener: ListenerRegistration?
    private var mySharedNight: SharedNight?
    /// Per-friend back-off for night listeners the server denied (expired, not yet TTL-deleted).
    private var nightRetries: [String: Task<Void, Never>] = [:]
    private var nightFailures: [String: Int] = [:]
    private static let retryDelays: [UInt64] = [120, 300, 900]

    /// Per friend, the unexpired ended copies (`shared_nights/{fid}/ended`): nights that
    /// ended and were since replaced in the main doc by a newer night.
    private var endedListeners: [String: ListenerRegistration] = [:]
    private var endedNights: [String: [SharedNight]] = [:]
    private var endedRetries: [String: Task<Void, Never>] = [:]
    private var endedFailures: [String: Int] = [:]
    /// Which attach of each friend's ended listener is current.
    private var endedTokens: [String: UUID] = [:]
    /// A denied ended query is most often one whose bound fell behind the server's
    /// clock, which a prompt re-attach fixes; after that, back off like the main doc.
    private static let endedRetryDelays: [UInt64] = [10, 120, 300, 900]
    /// The rules let a friend list ended copies only with a query bound at or after
    /// the server's request time, so the bound sits this far past the device clock:
    /// a copy within 10 min of expiring is left out, and a device clock up to 10 min
    /// behind still gets through.
    private static let endedQueryMargin: TimeInterval = 600
    private var myEndedListener: ListenerRegistration?
    private var myEndedToken = UUID()
    private var myEndedNights: [SharedNight] = []

    private var friendUids: [String] = []
    private var incomingUids: [String] = []
    private var outgoingUids: [String] = []
    private var blockedUids: [String] = []

    /// The signed-in uid while started; nil after sign-out.
    var currentUid: String? { uid }
    /// Everyone I've blocked, whether or not their profile has loaded.
    var blockedUidSet: Set<String> { Set(blockedUids) }
    /// This account's last contacts check when it is under 24 hours old and was
    /// made with the number the account has now; nil otherwise. Saved per uid
    /// (`ContactMatchCache`), so a relaunch or another visit to Find friends
    /// spends none of the server's two checks a day, and another account on this
    /// phone never sees it.
    func cachedContactMatches() -> ContactMatchResult? {
        guard let owner = FirebaseManager.shared.currentUserId() else { return nil }
        let cache = ContactMatchCache.load(uid: owner)
        guard ContactMatchCache.isFresh(cache, now: Date(), currentPhone: FirebaseManager.shared.phoneNumber) else {
            return nil
        }
        return cache?.result
    }

    /// Called after this account's phone number is added, changed or removed,
    /// since who can be found from contacts depends on it.
    func clearContactCache() {
        guard let owner = FirebaseManager.shared.currentUserId() else { return }
        ContactMatchCache.clear(uid: owner)
    }

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

        attachMyNight(uid, session: s)
        attachMyEnded(uid, session: s)
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
        endedListeners.values.forEach { $0.remove() }
        endedListeners = [:]
        endedRetries.values.forEach { $0.cancel() }
        endedRetries = [:]
        endedFailures = [:]
        endedTokens = [:]
        endedNights = [:]
        myNightListener?.remove()
        myNightListener = nil
        mySharedNight = nil
        myEndedListener?.remove()
        myEndedListener = nil
        myEndedNights = []
        // Thread listeners belong to this account; the next one starts clean.
        NightThreadStore.clearCache()
        ReactionPickerFocus.shared.close()
        friendUids = []
        incomingUids = []
        outgoingUids = []
        blockedUids = []
        profiles = [:]
        resolving = []
        uid = nil
        askedPushForIncoming = false
        // The overrides belong to this account. Their calls' late finishes and
        // timeouts check `session` and drop themselves.
        pending = PendingFriendActions()
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
        rebuildMyNights()
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

    /// A `public_profiles` doc, which has no "uid" field: its id is the uid.
    private nonisolated static func profile(uid: String, data: [String: Any]) -> FriendProfile? {
        FriendProfile.parse(data, uid: uid)
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
        feed = friends.flatMap { profile in
            FeedOrdering.merge(profile: profile, main: nights[profile.uid],
                               ended: endedNights[profile.uid] ?? [])
        }
        settlePending()
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

        for (fid, listener) in endedListeners where !wanted.contains(fid) {
            listener.remove()
            endedListeners[fid] = nil
            endedTokens[fid] = nil
        }
        for fid in Array(endedRetries.keys) where !wanted.contains(fid) {
            endedRetries[fid]?.cancel()
            endedRetries[fid] = nil
        }
        for fid in Array(endedFailures.keys) where !wanted.contains(fid) {
            endedFailures[fid] = nil
        }
        for fid in Array(endedNights.keys) where !wanted.contains(fid) {
            endedNights[fid] = nil
        }
        for fid in wanted where endedListeners[fid] == nil && endedRetries[fid] == nil {
            attachEnded(fid, session: s)
        }
    }

    /// `shared_nights/{uid}/ended`, unexpired copies only, the 10 that expire last
    /// (the newest) first. A friend's query must carry the `expires_at` bound or the
    /// rules deny it whole.
    private func endedQuery(_ uid: String, after bound: Date) -> Query {
        db.collection("shared_nights").document(uid).collection("ended")
            .whereField("expires_at", isGreaterThan: Timestamp(date: bound))
            .order(by: "expires_at", descending: true)
            .limit(to: 10)
    }

    /// Ended copies that can still be shown: parsed, ended and not yet expired.
    private static func unexpiredEnded(_ docs: [[String: Any]], now: Date) -> [SharedNight] {
        docs.compactMap { SharedNight(firestore: $0) }
            .filter { $0.endedAt != nil && $0.expiresAt > now }
    }

    private func attachEnded(_ fid: String, session s: Int) {
        endedListeners[fid]?.remove()
        // A callback already queued by the listener this replaces must not touch the new one.
        let token = UUID()
        endedTokens[fid] = token
        let bound = Date().addingTimeInterval(Self.endedQueryMargin)
        endedListeners[fid] = endedQuery(fid, after: bound)
            .addSnapshotListener { [weak self] snap, error in
                let failed = error != nil || snap == nil
                let docs = snap?.documents.map { $0.data() } ?? []
                Task { @MainActor [weak self] in
                    guard let self, self.session == s, self.endedTokens[fid] == token,
                          self.friendUids.contains(fid) else { return }
                    if failed {
                        // Keep what was shown (the feed still drops it on expiry): a denial
                        // here is usually a bound the server clock has passed, fixed by the
                        // quick re-attach. An unfriending removes the friend's nights anyway.
                        self.endedListeners[fid]?.remove()
                        self.endedListeners[fid] = nil
                        self.retryEnded(fid, session: s)
                        return
                    }
                    self.endedFailures[fid] = nil
                    self.endedNights[fid] = Self.unexpiredEnded(docs, now: Date())
                    self.rebuild()
                }
            }
    }

    /// One retry per friend, with growing delays, like `retryNight`.
    private func retryEnded(_ fid: String, session s: Int) {
        guard endedRetries[fid] == nil else { return }
        let failures = (endedFailures[fid] ?? 0) + 1
        endedFailures[fid] = failures
        let delay = Self.endedRetryDelays[min(failures - 1, Self.endedRetryDelays.count - 1)]
        endedRetries[fid] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self, self.session == s else { return }
            self.endedRetries[fid] = nil
            guard self.friendUids.contains(fid), self.endedListeners[fid] == nil else { return }
            self.attachEnded(fid, session: s)
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

    // MARK: - My own night

    /// The owner may always get their own `shared_nights` doc.
    private func attachMyNight(_ uid: String, session s: Int) {
        myNightListener?.remove()
        myNightListener = db.collection("shared_nights").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                let failed = error != nil
                let data = failed ? nil : snap?.data()
                Task { @MainActor [weak self] in
                    guard let self, self.session == s else { return }
                    if let data, let night = SharedNight(firestore: data), night.expiresAt > Date() {
                        self.mySharedNight = night
                    } else {
                        self.mySharedNight = nil
                    }
                    if failed {
                        // Dead listener; the next foreground attaches it again.
                        self.myNightListener?.remove()
                        self.myNightListener = nil
                    }
                    self.rebuildMyNights()
                }
            }
    }

    /// My ended copies. The owner may read all of them; the bound only skips expired
    /// copies TTL has not collected yet.
    private func attachMyEnded(_ uid: String, session s: Int) {
        myEndedListener?.remove()
        let token = UUID()
        myEndedToken = token
        myEndedListener = endedQuery(uid, after: Date())
            .addSnapshotListener { [weak self] snap, error in
                let failed = error != nil || snap == nil
                let docs = snap?.documents.map { $0.data() } ?? []
                Task { @MainActor [weak self] in
                    guard let self, self.session == s, self.myEndedToken == token else { return }
                    if failed {
                        // Dead listener; the next foreground attaches it again.
                        self.myEndedListener?.remove()
                        self.myEndedListener = nil
                        return
                    }
                    self.myEndedNights = Self.unexpiredEnded(docs, now: Date())
                    self.rebuildMyNights()
                }
            }
    }

    private func rebuildMyNights() {
        guard let profile = myProfile else {
            if !myNights.isEmpty { myNights = [] }
            return
        }
        myNights = FeedOrdering.merge(profile: profile, main: mySharedNight, ended: myEndedNights)
    }

    /// Back to the foreground: try every dead listener now instead of waiting out its back-off.
    /// Every ended-copy listener is attached again, live ones too: their `expires_at`
    /// bound was fixed at attach and the server clock may have passed it in the
    /// background. Their nights stay on screen until the new snapshot replaces them.
    private func reattachDeadNightListeners() {
        guard let uid else { return }
        let s = session
        if myNightListener == nil { attachMyNight(uid, session: s) }
        attachMyEnded(uid, session: s)
        nightRetries.values.forEach { $0.cancel() }
        nightRetries = [:]
        for fid in friendUids where nightListeners[fid] == nil {
            attachNight(fid, session: s)
        }
        endedRetries.values.forEach { $0.cancel() }
        endedRetries = [:]
        for fid in friendUids {
            attachEnded(fid, session: s)
        }
    }

    // MARK: - Actions (server callables)

    func claimUsername(_ name: String) async throws {
        try await FirebaseManager.shared.claimUsername(name)
    }

    /// Saves my display name ("" clears it) and shows the saved name at once,
    /// without waiting for the profile listener, which then confirms it.
    /// Returns the name as saved, nil when cleared.
    @discardableResult
    func setDisplayName(_ name: String) async throws -> String? {
        let s = session
        let saved = try await FirebaseManager.shared.setDisplayName(name)
        // Signed out or switched account while saving: that profile isn't shown any more.
        if session == s, var me = myProfile, me.name != saved {
            me.name = saved
            applyMyProfile(me, syncNight: false)
        }
        return saved
    }

    func search(_ q: String) async throws -> [FriendProfile] {
        try await FirebaseManager.shared.searchUsers(query: q)
    }

    func suggestions() async throws -> [PersonSuggestion] {
        try await FirebaseManager.shared.suggestFriends()
    }

    /// Checks the numbers, which spends one of the account's two checks a day,
    /// and saves the answer for this account for 24 hours.
    func contactMatches(phones: [String]) async throws -> ContactMatchResult {
        let owner = FirebaseManager.shared.currentUserId()
        let ownerPhone = FirebaseManager.shared.phoneNumber
        let checkedAt = Date()
        let result = try await FirebaseManager.shared.matchContacts(phones: phones)
        // Signed out, switched account or changed number while checking: keep nothing.
        if let owner, owner == FirebaseManager.shared.currentUserId(),
           let ownerPhone, ownerPhone == FirebaseManager.shared.phoneNumber {
            ContactMatchCache.save(ContactMatchCache(result: result, checkedAt: checkedAt, ownerPhone: ownerPhone),
                                   uid: owner)
        }
        return result
    }

    // MARK: - Friend requests (optimistic)

    /// Where I stand with `uid`, with any pending action on top. The base comes
    /// from the listeners' uid lists, not the profile lists, so a profile still
    /// loading doesn't read as "no relation" and flip a row back.
    func rowState(for uid: String) -> PendingFriendActions.RowState {
        pending.overlay(listenedState(for: uid), for: uid)
    }

    /// What the listeners alone say about `uid`.
    private func listenedState(for uid: String) -> PendingFriendActions.RowState {
        if friendUids.contains(uid) { return .friend }
        if incomingUids.contains(uid) { return .accept }
        if outgoingUids.contains(uid) { return .pending }
        return .add
    }

    /// Ends the overrides the listeners now show. Runs after every listener update.
    private func settlePending() {
        guard !pending.isEmpty else { return }
        var listened: [String: PendingFriendActions.RowState] = [:]
        for uid in pending.uids {
            listened[uid] = listenedState(for: uid)
        }
        pending.settle(listened)
    }

    /// Longest an override outlives its successful call when the listeners never
    /// show the change (offline, or a listener that died).
    private static let pendingTimeout: UInt64 = 10

    /// Shows `action` on `uid`'s row at once, then runs `call`, which returns
    /// what the server actually did. A failure puts the row back and rethrows,
    /// so the caller's alert says why. After a success the override stays until
    /// the listeners show the change (`settlePending`), or for at most 10 s.
    private func performOptimistic(
        _ action: PendingFriendActions.Action, for uid: String,
        _ call: () async throws -> PendingFriendActions.Action
    ) async throws {
        let s = session
        let ticket = pending.begin(action, for: uid)
        let done: PendingFriendActions.Action
        do {
            done = try await call()
        } catch {
            // After a sign-out `stop` has already cleared it.
            if session == s { pending.end(for: uid, ticket: ticket) }
            throw error
        }
        guard session == s else { return }
        let listened = listenedState(for: uid)
        guard pending.succeed(done, for: uid, ticket: ticket, listened: listened) else { return }
        let timeout = Self.pendingTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
            guard let self, self.session == s else { return }
            self.pending.end(for: uid, ticket: ticket)
        }
    }

    func sendRequest(to uid: String) async throws {
        try await performOptimistic(.requested, for: uid) {
            let status = try await FirebaseManager.shared.sendFriendRequest(toUid: uid)
            // They had already asked me, so the server made us friends.
            return status == "friends" ? .accepted : .requested
        }
        // Only reached on success: the first request sent is the moment to ask.
        Task { await PushRegistration.requestIfNeeded(sentCount: 1) }
    }

    func respond(to uid: String, accept: Bool) async throws {
        try await performOptimistic(accept ? .accepted : .declined, for: uid) {
            try await FirebaseManager.shared.respondToFriendRequest(fromUid: uid, accept: accept)
            return accept ? .accepted : .declined
        }
    }

    func cancelRequest(to uid: String) async throws {
        try await performOptimistic(.cancelled, for: uid) {
            try await FirebaseManager.shared.cancelFriendRequest(toUid: uid)
            return .cancelled
        }
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

    /// Reports a comment by `authorUid` on the night `key`.
    func reportComment(_ commentId: String, by authorUid: String, on key: NightKey) async throws {
        try await FirebaseManager.shared.reportComment(key, commentId: commentId, authorUid: authorUid)
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

// MARK: - Optimistic friend actions

/// Friend actions just taken on this phone, by uid, shown on the rows before
/// the server and the Firestore listeners confirm them. Each `begin` gets a
/// ticket, so an older call that finishes late never ends a newer action's
/// override.
nonisolated struct PendingFriendActions {
    nonisolated enum Action: Equatable {
        case requested, accepted, declined, cancelled
    }

    /// What a person's row offers: Add, Pending (my request is out), Friends,
    /// or Accept (they asked me).
    nonisolated enum RowState: Equatable {
        case add, pending, friend, accept
    }

    private var entries: [String: (action: Action, ticket: Int)] = [:]
    private var lastTicket = 0

    var isEmpty: Bool { entries.isEmpty }
    var uids: [String] { Array(entries.keys) }

    func action(for uid: String) -> Action? { entries[uid]?.action }

    func isPending(_ uid: String) -> Bool { entries[uid] != nil }

    /// Shows `action` for `uid`, replacing any earlier one. The returned ticket
    /// names this action to `end(for:ticket:)` and `succeed`.
    @discardableResult
    mutating func begin(_ action: Action, for uid: String) -> Int {
        lastTicket += 1
        entries[uid] = (action: action, ticket: lastTicket)
        return lastTicket
    }

    mutating func end(for uid: String) {
        entries[uid] = nil
    }

    /// Ends `uid`'s override only while it is still the one `ticket` began: a
    /// failed call rolls its own row back, never a newer action's.
    mutating func end(for uid: String, ticket: Int) {
        if entries[uid]?.ticket == ticket { entries[uid] = nil }
    }

    /// The call for `ticket` succeeded and the server did `done` (a request to
    /// someone who had already asked me makes us friends). Ends the override
    /// when `listened`, the listeners' state, already shows it. True while it
    /// still waits for them; false once ended, or when a newer action or the
    /// listeners got there first.
    mutating func succeed(_ done: Action, for uid: String, ticket: Int, listened: RowState) -> Bool {
        guard entries[uid]?.ticket == ticket else { return false }
        if Self.isReflected(done, in: listened) {
            entries[uid] = nil
            return false
        }
        entries[uid] = (action: done, ticket: ticket)
        return true
    }

    /// Ends every override whose uid's state in `listened` (from the listeners
    /// alone) shows its action. Uids not in `listened` are left alone.
    mutating func settle(_ listened: [String: RowState]) {
        for (uid, state) in listened {
            if let action = entries[uid]?.action, Self.isReflected(action, in: state) {
                entries[uid] = nil
            }
        }
    }

    /// `state` with `uid`'s pending action on top.
    func overlay(_ state: RowState, for uid: String) -> RowState {
        guard let action = entries[uid]?.action else { return state }
        switch action {
        case .requested:
            switch state {
            case .add: return .pending
            // To someone who had asked me, a request makes us friends.
            case .accept: return .friend
            case .pending, .friend: return state
            }
        case .accepted:
            // Also while their request is gone and the friendship is not in yet:
            // the two come through different listeners, in either order.
            return .friend
        case .declined:
            return state == .accept ? .add : state
        case .cancelled:
            return state == .pending ? .add : state
        }
    }

    /// True once the listeners alone show what `action` did.
    static func isReflected(_ action: Action, in state: RowState) -> Bool {
        switch action {
        case .requested: return state == .pending || state == .friend
        case .accepted: return state == .friend
        case .declined: return state != .accept
        case .cancelled: return state != .pending
        }
    }
}
