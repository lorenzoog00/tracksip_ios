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
    /// account (after a sign-out) is replaced.
    static func store(for key: NightKey, myUid: String) -> NightThreadStore {
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

    private var db: Firestore { Firestore.firestore() }

    init(key: NightKey, myUid: String) {
        self.key = key
        self.myUid = myUid
    }

    // MARK: - Lifecycle

    func start() {
        guard summaryListener == nil else { return }
        generation &+= 1
        let g = generation

        summaryListener = thread.addSnapshotListener { [weak self] snap, error in
            // An error (expired, unfriended) says nothing new; keep what is shown.
            guard error == nil, let snap else { return }
            let exists = snap.exists
            let data = snap.data()
            Task { @MainActor [weak self] in
                guard let self, self.generation == g else { return }
                // A missing doc is a thread nobody has touched yet.
                self.serverSummary = data.flatMap { ThreadSummary.parse($0) } ?? ThreadSummary()
                // The rules read the summary doc to allow my reaction doc, so that listener
                // is denied (and ended) while the summary is missing. Attach it, or attach
                // it again, once the summary exists.
                if exists { self.attachReactionListener(generation: g) }
                self.publishSummary()
            }
        }
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

    /// My own reaction doc. At most one listener: a live one is kept, a denied one is
    /// dropped by its error callback so the next summary snapshot can try again.
    private func attachReactionListener(generation g: Int) {
        guard !isOwnNight, reactionListener == nil, generation == g else { return }
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

    /// Tapping my reaction removes it; any other replaces it.
    func react(_ reaction: Reaction) async {
        guard !isOwnNight else { return }
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

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
        } catch {
            comments.removeAll { $0.id == pending.id }
            showSocialNotice(title: "Couldn't send comment", message: error.localizedDescription)
        }
    }

    func delete(_ comment: ThreadComment) async {
        guard !comment.isPending,
              let index = comments.firstIndex(where: { $0.id == comment.id })
        else { return }
        comments.remove(at: index)
        do {
            try await FirebaseManager.shared.deleteComment(key, id: comment.id)
        } catch {
            if !comments.contains(where: { $0.id == comment.id }) {
                comments.insert(comment, at: min(index, comments.count))
            }
            showSocialNotice(title: "Couldn't delete comment", message: error.localizedDescription)
        }
    }

    // MARK: - Full thread

    /// Reloads reactions and comments. Silent on failure: it runs on a timer while
    /// the sheet is open, and the last good state stays on screen.
    func refresh() async {
        guard let thread = try? await FirebaseManager.shared.nightThread(key) else { return }
        let pending = comments.filter(\.isPending)
        comments = thread.comments + pending
        reactedNames = thread.reactions
            .filter { $0.uid != myUid }
            .map { $0.username }
    }
}
