import Foundation
import Combine
import FirebaseFirestore

/// Reactions and comments on one shared night. Listens to the summary doc and to my
/// own reaction doc; the full thread comes from `getNightThread` via `refresh()`.
/// Reacting and commenting are optimistic and roll back with a notice on failure.
///
/// One store per night, shared through `cache`, so the feed card and the comment
/// sheet show the same state.
@MainActor
final class NightThreadStore: ObservableObject {
    static var cache: [NightKey: NightThreadStore] = [:]

    /// The cached store for this night, created on first use. A store from another
    /// account (after a sign-out) is replaced. With no signed-in user (an empty uid)
    /// the store is inert and uncached: it never touches a Firestore path.
    static func store(for key: NightKey, myUid: String) -> NightThreadStore {
        guard !myUid.isEmpty else { return NightThreadStore(key: key, myUid: "") }
        if let existing = cache[key], existing.myUid == myUid { return existing }
        cache[key]?.stop()
        let store = NightThreadStore(key: key, myUid: myUid)
        cache[key] = store
        return store
    }

    /// Sign-out: stop and forget every store.
    static func clearCache() {
        cache.values.forEach { $0.stop() }
        cache = [:]
    }

    let key: NightKey
    let myUid: String
    /// Shown on my pending comments until the server confirms them.
    var myUsername = ""

    /// Counts include my optimistic reaction.
    @Published private(set) var summary = ThreadSummary()
    @Published private(set) var myReaction: Reaction?
    /// Oldest first; my unconfirmed comments last, flagged `isPending`.
    @Published private(set) var comments: [ThreadComment] = []
    /// Usernames of everyone else who reacted, oldest first. "you" is up to the view
    /// (from `myReaction`).
    @Published private(set) var reactedNames: [String] = []

    var isOwnNight: Bool { key.owner == myUid }
    /// False for the inert store made with no signed-in user.
    var hasUser: Bool { !myUid.isEmpty }

    /// The server said this night is gone or not ours to see (`getNightThread`
    /// answered not-found or permission-denied): the sheet says so instead of
    /// showing an empty thread with a working composer.
    @Published private(set) var isUnavailable = false

    /// What the server last said: the summary doc and my reaction doc.
    private var serverSummary = ThreadSummary()
    private var serverReaction: Reaction?
    /// Reaction calls in flight; the latest one decides `myReaction` when it returns.
    private var reactSeq = 0
    private var reactInFlight = 0
    /// The newest call whose answer is in `serverReaction`; an older answer that
    /// returns late must not overwrite a newer one.
    private var lastAppliedSeq = 0

    private var summaryListener: ListenerRegistration?
    private var reactionListener: ListenerRegistration?
    /// Bumped by every start/stop so a late snapshot from a removed listener is dropped.
    private var generation = 0
    /// Re-attaching the summary listener after Firestore ended it: the wait before the
    /// next try (doubling up to a minute) and how many tries are left before waiting
    /// for the next `start()` (a view appearing again).
    private var summaryRetryDelay: Duration = .seconds(2)
    private var summaryRetriesLeft = 0
    private static let summaryRetries = 6

    /// Bumped whenever a send or delete finishes, so a `refresh()` that was already
    /// loading (and may predate it) throws its answer away.
    private var mutations = 0
    /// Comments with a delete in flight; a refresh must not bring them back.
    private var deleting: Set<String> = []

    private var db: Firestore { Firestore.firestore() }

    init(key: NightKey, myUid: String) {
        self.key = key
        self.myUid = myUid
    }

    // MARK: - Lifecycle

    /// Attaches the listeners. A no-op while the summary listener is live; once
    /// Firestore has ended it (and the retries gave up), this attaches it again.
    func start() {
        guard hasUser, summaryListener == nil else { return }
        // Also cancels a pending retry and drops a reaction listener left from before.
        stop()
        let g = generation
        summaryRetryDelay = .seconds(2)
        summaryRetriesLeft = Self.summaryRetries
        attachSummaryListener(generation: g)
        attachReactionListener(generation: g)
    }

    func stop() {
        generation &+= 1
        summaryListener?.remove()
        summaryListener = nil
        reactionListener?.remove()
        reactionListener = nil
    }

    private var thread: DocumentReference {
        db.collection("night_threads").document(key.id)
    }

    private func attachSummaryListener(generation g: Int) {
        guard summaryListener == nil, generation == g else { return }
        summaryListener = thread.addSnapshotListener { [weak self] snap, error in
            let failed = error != nil || snap == nil
            let data = failed ? nil : snap?.data()
            Task { @MainActor [weak self] in
                guard let self, self.generation == g else { return }
                if failed {
                    // Firestore has ended this listener: the night expired, we were
                    // unfriended, or a denial was transient. Keep what is shown, forget
                    // the listener and try again in a while.
                    self.summaryListener?.remove()
                    self.summaryListener = nil
                    self.retrySummaryListener(generation: g)
                    return
                }
                self.summaryRetryDelay = .seconds(2)
                self.summaryRetriesLeft = Self.summaryRetries
                // A missing doc is a thread nobody has touched yet.
                self.serverSummary = data.flatMap { ThreadSummary.parse($0) } ?? ThreadSummary()
                // The thread is readable, so my reaction doc is too: attach its
                // listener again if a denial ended it.
                self.attachReactionListener(generation: g)
                self.publishSummary()
            }
        }
    }

    /// Tries the summary listener again after a back-off, a few times; after that
    /// the next `start()` does.
    private func retrySummaryListener(generation g: Int) {
        guard summaryRetriesLeft > 0 else { return }
        summaryRetriesLeft -= 1
        let delay = summaryRetryDelay
        summaryRetryDelay = min(delay * 2, .seconds(60))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.generation == g else { return }
            self.attachSummaryListener(generation: g)
        }
    }

    /// My own reaction doc. At most one listener: a live one is kept, a denied one is
    /// dropped by its error callback so the next summary snapshot can try again. The
    /// rules allow it while the night is visible, like the summary.
    private func attachReactionListener(generation g: Int) {
        guard reactionListener == nil, generation == g else { return }
        reactionListener = thread.collection("reactions").document(myUid)
            .addSnapshotListener { [weak self] snap, error in
                let failed = error != nil
                let raw = failed ? nil : (snap?.data()?["emoji"] as? String)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == g else { return }
                    if failed {
                        // Firestore has ended this listener; forget it.
                        self.reactionListener?.remove()
                        self.reactionListener = nil
                        return
                    }
                    self.serverReaction = raw.flatMap { Reaction(rawValue: $0) }
                    if self.reactInFlight == 0 { self.myReaction = self.serverReaction }
                    self.publishSummary()
                }
            }
    }

    /// Server counts, adjusted for a reaction of mine the server has not reported yet.
    private func publishSummary() {
        var next = serverSummary
        if myReaction != serverReaction {
            next.counts = ReactionMath.apply(counts: next.counts, old: serverReaction, new: myReaction)
        }
        if summary != next { summary = next }
    }

    // MARK: - Reactions

    /// Tapping my reaction removes it; any other replaces it. The server is sent the
    /// reaction wanted (nil to remove), never a toggle, so a repeated or reordered
    /// call can't flip it.
    func react(_ reaction: Reaction) async {
        guard hasUser, !isUnavailable else { return }
        let target: Reaction? = (myReaction == reaction) ? nil : reaction
        reactSeq &+= 1
        let seq = reactSeq
        reactInFlight += 1
        myReaction = target
        publishSummary()
        do {
            let confirmed = try await FirebaseManager.shared.reactToNight(key, reaction: target)
            reactInFlight -= 1
            // The callable's answer is the server's state; don't wait for the listener,
            // which may be dead (see attachReactionListener).
            if seq > lastAppliedSeq {
                lastAppliedSeq = seq
                serverReaction = confirmed
            }
            if seq == reactSeq { myReaction = confirmed }
        } catch {
            reactInFlight -= 1
            if seq == reactSeq { myReaction = serverReaction }
            showSocialNotice(title: "Couldn't react", message: error.localizedDescription)
        }
        publishSummary()
    }

    // MARK: - Comments

    /// Sends a comment, shown pending until the server confirms it. Returns whether
    /// it was sent; on failure the store has already shown why.
    @discardableResult
    func send(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasUser, !isUnavailable, !trimmed.isEmpty else { return false }
        let pending = ThreadComment(
            id: "pending-\(UUID().uuidString)",
            uid: myUid,
            username: myUsername,
            text: trimmed,
            mentions: [],
            at: Date(),
            isPending: true
        )
        comments.append(pending)
        defer { mutations &+= 1 }
        do {
            var sent = try await FirebaseManager.shared.addComment(key, text: trimmed)
            sent.uid = myUid
            if sent.username.isEmpty { sent.username = myUsername }
            if let index = comments.firstIndex(where: { $0.id == pending.id }) {
                // A refresh may already have brought the confirmed comment in.
                if comments.contains(where: { $0.id == sent.id }) {
                    comments.remove(at: index)
                } else {
                    comments[index] = sent
                }
            }
            return true
        } catch {
            comments.removeAll { $0.id == pending.id }
            showSocialNotice(title: "Couldn't send comment", message: error.localizedDescription)
            return false
        }
    }

    /// Removes a comment at once and puts it back if the server refuses. Returns
    /// whether it was deleted.
    @discardableResult
    func delete(_ comment: ThreadComment) async -> Bool {
        guard hasUser, !comment.isPending,
              let index = comments.firstIndex(where: { $0.id == comment.id })
        else { return false }
        comments.remove(at: index)
        deleting.insert(comment.id)
        defer {
            deleting.remove(comment.id)
            mutations &+= 1
        }
        do {
            try await FirebaseManager.shared.deleteComment(key, id: comment.id)
            return true
        } catch {
            if !comments.contains(where: { $0.id == comment.id }) {
                comments.insert(comment, at: min(index, comments.count))
            }
            showSocialNotice(title: "Couldn't delete comment", message: error.localizedDescription)
            return false
        }
    }

    // MARK: - Full thread

    /// Reloads reactions and comments. Silent on failure: it runs on a timer while
    /// the sheet is open, and the last good state stays on screen. An answer that a
    /// send or delete finished during is dropped, since it may predate that change
    /// (bringing a deleted comment back or losing a sent one); the next poll loads
    /// the thread again.
    func refresh() async {
        guard hasUser else { return }
        let started = mutations
        let thread: (reactions: [(uid: String, username: String, reaction: Reaction)], comments: [ThreadComment])
        do {
            thread = try await FirebaseManager.shared.nightThread(key)
        } catch {
            // Gone for good (expired, deleted, unfriended or blocked): say so. Any other
            // failure keeps the last good state.
            if FirebaseManager.isNightUnavailable(error) { isUnavailable = true }
            return
        }
        isUnavailable = false
        guard mutations == started else { return }
        let pending = comments.filter(\.isPending)
        comments = thread.comments.filter { !deleting.contains($0.id) } + pending
        reactedNames = thread.reactions
            .filter { $0.uid != myUid }
            .map { $0.username }
    }
}
