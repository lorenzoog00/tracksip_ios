import Foundation
import SwiftUI

// MARK: - Pure helpers

/// Someone who can be suggested after an `@`, and why they are on the list.
nonisolated struct MentionCandidate: Equatable, Identifiable {
    nonisolated enum Source: Equatable {
        case owner, reacted, commented, friend
    }

    let username: String
    let source: Source

    var id: String { username.lowercased() }

    init(username: String, source: Source) {
        self.username = username
        self.source = source
    }
}

nonisolated enum MentionSuggestions {
    static let defaultLimit = 5

    /// Names starting with `query` (case-insensitive): the owner, then people who
    /// reacted, then commenters, then friends. Each name once, in its first group;
    /// never `me`. The server decides who can really be mentioned.
    static func candidates(query: String, owner: String, reacted: [String], commenters: [String],
                           friends: [String], me: String, limit: Int = MentionSuggestions.defaultLimit) -> [MentionCandidate] {
        let prefix = query.lowercased()
        let mine = me.lowercased()
        let groups: [([String], MentionCandidate.Source)] = [
            ([owner], .owner), (reacted, .reacted), (commenters, .commented), (friends, .friend)
        ]
        var seen: Set<String> = []
        var result: [MentionCandidate] = []
        for (names, source) in groups {
            for name in names {
                let key = name.lowercased()
                guard !key.isEmpty, key != mine, key.hasPrefix(prefix), !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(MentionCandidate(username: name, source: source))
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// Replaces the `@partial` the cursor is in (and the rest of that name, if the
    /// cursor sits inside it) with `@name `. The new cursor lands after the space.
    /// nil when the cursor is not in a mention.
    static func complete(_ text: String, cursor: Int, with name: String) -> (text: String, cursor: Int)? {
        let chars = Array(text)
        let caret = min(max(0, cursor), chars.count)
        guard MentionText.activeQuery(in: text, cursor: caret) != nil else { return nil }
        var start = caret - 1
        while start >= 0, chars[start] != "@" { start -= 1 }
        guard start >= 0 else { return nil }
        var end = caret
        while end < chars.count, MentionText.isNameCharacter(chars[end]) { end += 1 }
        let spaceFollows = end < chars.count && chars[end] == " "
        let inserted = Array("@" + name + (spaceFollows ? "" : " "))
        let result = Array(chars[..<start]) + inserted + Array(chars[end...])
        return (String(result), start + inserted.count + (spaceFollows ? 1 : 0))
    }

    /// The picked names still written as `@name` in `text`, in `picked` order.
    static func stillMentioned(_ picked: [String], in text: String) -> [String] {
        let mentions = picked.map { ThreadMention(uid: "", username: $0) }
        let written = Set(MentionText.segments(text, mentions: mentions)
            .filter { $0.1 }
            .map { String($0.0.dropFirst()).lowercased() })
        return picked.filter { written.contains($0.lowercased()) }
    }
}

nonisolated enum CommentDraft {
    static let maxLength = 200
    /// The counter shows from here on.
    static let counterFrom = 180

    /// What the server counts: trimmed, one per Unicode scalar (JS `Array.from`).
    static func length(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }

    static func canSend(_ text: String) -> Bool {
        let count = length(text)
        return count > 0 && count <= maxLength
    }
}

nonisolated enum CommentRowKeys {
    /// Stable row identities. My comments are keyed by text and occurrence, so a
    /// pending comment keeps its row when the server's copy (new id) replaces it
    /// and it can solidify in place instead of leaving and re-entering.
    static func keys(_ comments: [ThreadComment], myUid: String) -> [String] {
        var seen: [String: Int] = [:]
        return comments.map { comment in
            guard comment.uid == myUid else { return comment.id }
            let n = seen[comment.text, default: 0]
            seen[comment.text] = n + 1
            return "mine|\(n)|\(comment.text)"
        }
    }
}

// MARK: - Sheet

/// One night's conversation: the six reactions (yours marked) and who reacted, the
/// comments, and a composer that suggests `@names`. Polls the full thread every 5 s
/// while it is up.
struct NightThreadSheet: View {
    let key: NightKey
    let ownerName: String

    @EnvironmentObject private var friends: FriendsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store: NightThreadStore
    @StateObject private var actions = FriendActionCoordinator()

    @State private var draft = ""
    /// The composer's cursor, so a mention is completed where it is typed.
    @FocusState private var composerFocused: Bool
    /// Names picked from the suggestions; the ones still in the draft show as pills.
    @State private var picked: [String] = []
    @State private var detent: PresentationDetent = .medium
    @State private var reportTarget: ThreadComment?
    @State private var burst: Reaction?
    @State private var burstID = 0

    private static let bottomID = "thread-bottom"

    init(key: NightKey, ownerName: String) {
        self.key = key
        self.ownerName = ownerName
        let myUid = FirebaseManager.shared.currentUserId() ?? ""
        _store = ObservedObject(wrappedValue: NightThreadStore.store(for: key, myUid: myUid))
    }

    var body: some View {
        let rows = commentRows
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 1)
            comments(rows)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .background(AppColors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(AppColors.background)
        .friendActionDialogs(actions)
        .confirmationDialog(
            "Report @\(reportTarget.map(displayName) ?? "")?",
            isPresented: reportBinding,
            titleVisibility: .visible,
            presenting: reportTarget
        ) { comment in
            Button("Report", role: .destructive) { report(comment) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("We'll review their username and this comment.")
        }
        // The app's notices are hosted under the sheet; show them on it too.
        .noticeHost()
        .onAppear {
            syncUsername()
            store.start()
        }
        .onChange(of: friends.myProfile?.username) { _, _ in syncUsername() }
        .onChange(of: composerFocused) { _, focused in
            // Typing wants room: grow to full height.
            if focused && detent != .large {
                withAnimation(sheetAnimation) { detent = .large }
            }
        }
        .task {
            await store.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
                await store.refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                // ownerName is "" when a push opened a night whose owner isn't loaded.
                Text(store.isOwnNight ? "Your night" : (ownerName.isEmpty ? "Comments" : "@\(ownerName)'s night"))
                    .font(.headline)
                    .foregroundStyle(AppColors.text)
                    .lineLimit(1)
                Text(commentCountText)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .contentTransition(.numericText(value: Double(visibleCommentCount)))
                    .animation(changeAnimation, value: visibleCommentCount)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // The same 🍻 / 💧 pills as the card, counts included. Everyone can
            // react, the night's owner too.
            ReactionBar(store: store, canReact: true)

            reactedLine
        }
        .padding(.top, 22)
        .padding(.bottom, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
    }

    /// "Reacted: @beto, @lu, you".
    private var reactedLine: some View {
        var names = visibleReactors.map { "@\($0)" }
        if store.myReaction != nil { names.append("you") }
        var text = AttributedString(names.isEmpty ? "No reactions yet" : "Reacted: ")
        text.foregroundColor = AppColors.textSecondary
        if !names.isEmpty {
            var list = AttributedString(names.joined(separator: ", "))
            list.foregroundColor = AppColors.text
            text += list
        }
        return Text(text)
            .font(.footnote)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .contentTransition(.opacity)
            .animation(changeAnimation, value: names)
    }

    // MARK: - Comments

    private func comments(_ rows: [CommentRow]) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if rows.isEmpty {
                            emptyComments
                                .transition(.opacity)
                        }
                        ForEach(rows) { row in
                            commentRow(row.comment, now: context.date)
                                .id(row.id)
                                .transition(insertTransition)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .animation(listAnimation, value: rows.map(\.id))
                    .animation(listAnimation, value: rows.map(\.comment.isPending))
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.comments.last?.id) { _, _ in
                    // My comment just went out: bring it into view.
                    guard let last = store.comments.last, last.isPending else { return }
                    withAnimation(listAnimation) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyComments: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityHidden(true)
            Text("No comments yet")
                .font(.headline)
                .foregroundStyle(AppColors.text)
            Text(store.isOwnNight ? "Your friends' comments show up here."
                 : (ownerName.isEmpty ? "Say something." : "Say something to @\(ownerName)."))
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
    }

    private func commentRow(_ comment: ThreadComment, now: Date) -> some View {
        let name = displayName(comment)
        let canDelete = !comment.isPending && (comment.uid == store.myUid || store.isOwnNight)
        let canReport = !comment.isPending && comment.uid != store.myUid
        return HStack(alignment: .top, spacing: 10) {
            AvatarView(profile: profile(uid: comment.uid, username: name), size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("@\(name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if comment.uid == key.owner {
                        Text("Owner")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background { Capsule().fill(AppColors.accentDim) }
                    }
                    Text(comment.isPending ? "Sending…" : FriendNightFormat.ago(now.timeIntervalSince(comment.at)))
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.opacity)
                }
                Text(commentText(comment))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.disabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: 14).fill(AppColors.background) }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        // Sent at 60 %, solid once the server has it.
        .opacity(comment.isPending ? 0.6 : 1)
        .contextMenu {
            if canDelete {
                Button(role: .destructive) {
                    delete(comment)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if canReport {
                Button {
                    reportTarget = comment
                } label: {
                    Label("Report", systemImage: "flag")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(comment, name: name, now: now))
        .accessibilityHint(canDelete || canReport ? "Long press for options" : "")
        .accessibilityAction(named: "Delete") {
            if canDelete { delete(comment) }
        }
        .accessibilityAction(named: "Report") {
            if canReport { reportTarget = comment }
        }
    }

    /// The text with mentioned names as gold pills; any other `@name` stays plain.
    private func commentText(_ comment: ThreadComment) -> AttributedString {
        var result = AttributedString()
        for (text, isMention) in MentionText.segments(comment.text, mentions: comment.mentions) {
            var part = AttributedString(text)
            if isMention {
                part.foregroundColor = AppColors.accent
                part.backgroundColor = AppColors.accentDim
                part.font = Font.subheadline.weight(.semibold)
            } else {
                part.foregroundColor = AppColors.text.opacity(0.92)
            }
            result += part
        }
        return result
    }

    private func accessibilityText(_ comment: ThreadComment, name: String, now: Date) -> String {
        let when = comment.isPending ? "sending" : FriendNightFormat.ago(now.timeIntervalSince(comment.at))
        return "@\(name), \(when): \(comment.text)"
    }

    // MARK: - Composer

    private var composer: some View {
        let length = CommentDraft.length(draft)
        let canSend = CommentDraft.canSend(draft)
        let suggestions = mentionSuggestions
        let pills = MentionSuggestions.stillMentioned(picked, in: draft)
        return VStack(spacing: 8) {
            if !suggestions.isEmpty {
                suggestionList(suggestions)
                    .transition(suggestionTransition)
            }
            if !pills.isEmpty {
                pillRow(pills)
                    .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                // No `selection:` binding: on iOS 18 the cursor-tracking TextField
                // crashed the app as soon as the field was tapped. Mentions are
                // completed at the end of the text instead, which is where people type.
                TextField(
                    "Add a comment",
                    text: $draft,
                    prompt: Text("Add a comment…").foregroundStyle(AppColors.textTertiary),
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.body)
                .foregroundStyle(AppColors.text)
                .tint(AppColors.accent)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 22).fill(AppColors.surfaceElevated)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(length > CommentDraft.maxLength ? AppColors.danger.opacity(0.7) : AppColors.border,
                                lineWidth: 1)
                }
                .accessibilityLabel("Comment")

                sendButton(enabled: canSend)
            }
            if length >= CommentDraft.counterFrom {
                Text("\(length)/\(CommentDraft.maxLength)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(length > CommentDraft.maxLength ? AppColors.danger : AppColors.textSecondary)
                    .contentTransition(.numericText(value: Double(length)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 60)
                    .transition(.opacity)
                    .accessibilityLabel(length > CommentDraft.maxLength
                                        ? "\(length - CommentDraft.maxLength) characters over the limit"
                                        : "\(CommentDraft.maxLength - length) characters left")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            AppColors.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(AppColors.border).frame(height: 1)
                }
                .ignoresSafeArea()
        }
        .animation(suggestionAnimation, value: suggestions.map(\.id))
        .animation(popAnimation, value: pills)
        .animation(changeAnimation, value: length >= CommentDraft.counterFrom)
        .animation(changeAnimation, value: length)
    }

    private func sendButton(enabled: Bool) -> some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Color.black : AppColors.textTertiary)
                .frame(width: 36, height: 36)
                .background {
                    Circle().fill(enabled ? AppColors.accent : Color.white.opacity(0.08))
                }
                .scaleEffect(enabled || reduceMotion ? 1 : 0.88)
                // 44 × 44 hit target around the 36 pt circle.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.55),
                   value: enabled)
        .accessibilityLabel("Send")
    }

    private func suggestionList(_ suggestions: [MentionCandidate]) -> some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { candidate in
                Button {
                    pick(candidate.username)
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(profile: profile(username: candidate.username), size: 30)
                        Text("@\(candidate.username)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(sourceLabel(candidate.source))
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SuggestionPressStyle())
                .transition(.opacity)
                .accessibilityLabel("Mention @\(candidate.username)")
                if candidate.id != suggestions.last?.id {
                    Rectangle()
                        .fill(AppColors.border.opacity(0.6))
                        .frame(height: 1)
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.surfaceElevated)
                .shadow(color: .black.opacity(0.4), radius: 12, y: -2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16).stroke(AppColors.rimLight, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// The names picked so far, as pills that pop in.
    private func pillRow(_ pills: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Mentioning")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                ForEach(pills, id: \.self) { name in
                    Text("@\(name)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background { Capsule().fill(AppColors.accentDim) }
                        .overlay { Capsule().stroke(AppColors.accent.opacity(0.35), lineWidth: 1) }
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sourceLabel(_ source: MentionCandidate.Source) -> String {
        switch source {
        case .owner: return "Owner"
        case .reacted: return "Reacted"
        case .commented: return "Commented"
        case .friend: return "Friend"
        }
    }

    // MARK: - Data

    private struct CommentRow: Identifiable {
        let id: String
        let comment: ThreadComment
    }

    private var blockedUids: Set<String> { Set(friends.blocked.map(\.uid)) }

    /// Comments minus anyone I blocked (the server filters too; this covers
    /// listener and pending data).
    private var visibleComments: [ThreadComment] {
        let blocked = blockedUids
        return store.comments.filter { !blocked.contains($0.uid) }
    }

    private var commentRows: [CommentRow] {
        let visible = visibleComments
        let keys = CommentRowKeys.keys(visible, myUid: store.myUid)
        return zip(keys, visible).map { CommentRow(id: $0.0, comment: $0.1) }
    }

    private var visibleCommentCount: Int {
        visibleComments.filter { !$0.isPending }.count
    }

    private var commentCountText: String {
        let count = visibleCommentCount
        if count == 0 { return "No comments" }
        return count == 1 ? "1 comment" : "\(count) comments"
    }

    /// `reactedNames` holds names only, so blocks are matched by username.
    private var visibleReactors: [String] {
        let blocked = Set(friends.blocked.map { $0.username.lowercased() })
        return store.reactedNames.filter { !blocked.contains($0.lowercased()) }
    }

    private var myName: String {
        friends.myProfile?.username ?? store.myUsername
    }

    private func displayName(_ comment: ThreadComment) -> String {
        if !comment.username.isEmpty { return comment.username }
        return comment.uid == store.myUid ? myName : ""
    }

    private func profile(uid: String, username: String) -> FriendProfile {
        if let me = friends.myProfile, me.uid == uid { return me }
        if let friend = friends.friends.first(where: { $0.uid == uid }) { return friend }
        return FriendProfile(uid: uid, username: username, photoURL: nil, avatarColor: "")
    }

    private func profile(username: String) -> FriendProfile {
        if let friend = friends.friends.first(where: {
            $0.username.caseInsensitiveCompare(username) == .orderedSame
        }) {
            return friend
        }
        return FriendProfile(uid: username, username: username, photoURL: nil, avatarColor: "")
    }

    /// Where mentions are completed: the end of the text (see the TextField).
    private var cursor: Int { draft.count }

    private var mentionSuggestions: [MentionCandidate] {
        guard composerFocused,
              let query = MentionText.activeQuery(in: draft, cursor: cursor)
        else { return [] }
        let blocked = Set(friends.blocked.map { $0.username.lowercased() })
        let commenters = visibleComments.reversed()
            .filter { !$0.isPending }
            .map(\.username)
        return MentionSuggestions.candidates(
            query: query,
            owner: ownerName,
            reacted: visibleReactors,
            commenters: commenters.filter { !blocked.contains($0.lowercased()) },
            friends: friends.friends.map(\.username),
            me: myName
        )
    }

    // MARK: - Actions

    private func syncUsername() {
        if let me = friends.myProfile?.username, !me.isEmpty { store.myUsername = me }
    }

    private func react(_ reaction: Reaction) {
        let adding = store.myReaction != reaction
        Haptics.shared.play(.selection)
        if adding && !reduceMotion {
            burstID &+= 1
            burst = reaction
            let id = burstID
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                if burstID == id { burst = nil }
            }
        }
        Task { await store.react(reaction) }
    }

    private func pick(_ name: String) {
        guard let done = MentionSuggestions.complete(draft, cursor: cursor, with: name) else { return }
        Haptics.shared.play(.selection)
        withAnimation(popAnimation) {
            draft = done.text
            if !picked.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                picked.append(name)
            }
        }
    }

    private func send() {
        let text = draft
        guard CommentDraft.canSend(text) else { return }
        let mentioned = picked
        Haptics.shared.play(.light)
        draft = ""
        picked = []
        Task {
            let sent = await store.send(text)
            // It failed (the store showed why): give the text back to try again,
            // unless something new has been typed meanwhile.
            if !sent && draft.isEmpty {
                draft = text
                picked = mentioned
            }
        }
    }

    private func delete(_ comment: ThreadComment) {
        Haptics.shared.play(.warning)
        Task { await store.delete(comment) }
    }

    /// Reports the comment itself (the server keeps a copy of its text with the
    /// author's username); the thanks alert then offers to block the author.
    private func report(_ comment: ThreadComment) {
        let author = profile(uid: comment.uid, username: displayName(comment))
        actions.reportComment(comment.id, by: author, on: key, store: friends)
    }

    private var reportBinding: Binding<Bool> {
        Binding(
            get: { reportTarget != nil },
            set: { if !$0 { reportTarget = nil } }
        )
    }

    // MARK: - Motion

    private var changeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.7)
    }

    private var listAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    private var sheetAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85)
    }

    private var suggestionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.34, dampingFraction: 0.8)
    }

    /// A picked name pops in.
    private var popAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.5)
    }

    private var insertTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var suggestionTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

/// A suggestion row: highlights while pressed.
private struct SuggestionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.06) : Color.clear)
    }
}
