import SwiftUI

/// The Social tab: pick a username first, then the friends feed.
struct SocialRootView: View {
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var firebase: FirebaseManager
    /// The one-time "Add your number" ask (see `promptForPhoneIfNeeded`).
    @State private var showPhonePrompt = false
    @State private var showSearch = false
    @State private var showFriends = false
    @State private var showProfile = false
    /// FeedView's own thread sheet or pushed night is up.
    @State private var feedCovered = false
    /// The night a tapped push opened, presented over the feed.
    @State private var pushedThread: NightKey?
    @State private var pushedThreadOwnerName = ""
    /// Waits for the stack to reset before presenting `pushedThread`; replaced and
    /// cancelled by every newer push, so an older one can never land last.
    @State private var pushedThreadTask: Task<Void, Never>?
    /// Changing this rebuilds the navigation stack: every pushed screen pops and
    /// every sheet presented inside it closes.
    @State private var stackID = UUID()

    var body: some View {
        NavigationStack {
            Group {
            if !friends.profileLoaded {
                // Before the first snapshot a missing profile is not "no username" yet.
                ZStack {
                    AppColors.background.ignoresSafeArea()
                    ProgressView().tint(AppColors.accent)
                }
            } else if friends.myProfile == nil {
                ChooseUsernameView(mode: .create)
            } else {
                feed
                    .sheet(isPresented: friendLinkBinding) {
                        if let name = appState.pendingFriendLink {
                            FriendLinkSheet(username: name)
                        }
                    }
                    .sheet(item: $pushedThread) { key in
                        NightThreadSheet(key: key, ownerName: pushedThreadOwnerName)
                    }
                    // Any way it closes counts as answered, a swipe down included.
                    .sheet(isPresented: $showPhonePrompt, onDismiss: { markPhonePromptAnswered() }) {
                        AddPhoneView { added in
                            markPhonePromptAnswered()
                            showPhonePrompt = false
                            if added { friends.clearContactCache() }
                        }
                    }
                    // A tapped reaction/comment push. Only here on the feed, so someone
                    // still choosing a username gets the sheet right after.
                    .onAppear(perform: openPendingThread)
                    .onChange(of: appState.pendingThread) { _, _ in openPendingThread() }
                    .onAppear(perform: promptForPhoneIfNeeded)
            }
            }
            // On every Social root state, choosing a username included, so there is
            // always a way back to Home.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { AppTabSwitcher() }
            }
        }
        .id(stackID)
    }

    /// Attached to the feed only, so a user still choosing a username sees the sheet after.
    private var friendLinkBinding: Binding<Bool> {
        Binding(
            get: { appState.pendingFriendLink != nil },
            set: { if !$0 { appState.pendingFriendLink = nil } }
        )
    }

    /// Opens a pushed night directly over the feed. When anything covers the feed (a
    /// pushed screen, the friend-link sheet, the feed's own thread sheet or pushed
    /// night, or an earlier pushed thread) the stack is reset to the bare feed first
    /// and the sheet follows once that has settled.
    private func openPendingThread() {
        guard let key = appState.pendingThread else { return }
        appState.pendingThread = nil
        // Also here: if this runs before RootView's handler, that one sees nil.
        appState.selectedTab = .social
        let name = ownerName(for: key.owner)
        // An earlier open still waiting means the reset it started may still be animating.
        let wasWaiting = pushedThreadTask != nil
        pushedThreadTask?.cancel()
        pushedThreadTask = nil

        let covered = wasWaiting || showSearch || showFriends || showProfile || feedCovered
            || appState.pendingFriendLink != nil || pushedThread != nil || showPhonePrompt
        guard covered else {
            pushedThreadOwnerName = name
            pushedThread = key
            return
        }
        showSearch = false
        showFriends = false
        showProfile = false
        feedCovered = false
        pushedThread = nil
        showPhonePrompt = false
        appState.pendingFriendLink = nil
        stackID = UUID()
        pushedThreadTask = Task {
            // Let the dismissals finish, or the new sheet is dropped.
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, appState.selectedTab == .social,
                  friends.myProfile != nil else { return }
            pushedThreadOwnerName = name
            pushedThread = key
            pushedThreadTask = nil
        }
    }

    /// Asks people who had a username before phone numbers existed, once per account
    /// on this phone. Checked when the feed appears, never polled, and skipped while
    /// a pushed thread or a friend link is showing or on its way, so it never stacks
    /// on them. Also skipped while Social is hidden behind Home: the feed can first
    /// appear there when the profile finishes loading after a tab switch.
    private func promptForPhoneIfNeeded() {
        guard appState.selectedTab == .social, !showPhonePrompt,
              appState.pendingThread == nil, pushedThread == nil, pushedThreadTask == nil,
              appState.pendingFriendLink == nil,
              !showSearch, !showFriends, !showProfile, !feedCovered,
              let uid = firebase.currentUserId() else { return }
        if PhonePrompt.shouldPrompt(hasPhone: firebase.phoneNumber != nil,
                                    hasUsername: friends.myProfile != nil,
                                    dismissed: PhonePrompt.isDismissed(uid: uid)) {
            showPhonePrompt = true
        }
    }

    private func markPhonePromptAnswered() {
        guard let uid = firebase.currentUserId() else { return }
        PhonePrompt.markDismissed(uid: uid)
    }

    /// "" when the owner is neither me nor a loaded friend; the sheet copes.
    private func ownerName(for uid: String) -> String {
        if let me = friends.myProfile, me.uid == uid { return me.username }
        return friends.friends.first { $0.uid == uid }?.username ?? ""
    }

    private var feed: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if friends.incoming.count > 0 {
                    Button {
                        showFriends = true
                    } label: {
                        HStack {
                            Text(friends.incoming.count == 1 ? "1 friend request" : "\(friends.incoming.count) friend requests")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(14)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                }
                FeedView(isCovered: $feedCovered, onAddFriend: { showSearch = true })
            }
        }
        // State-driven rather than value-less NavigationLinks, so a pushed thread can
        // pop every one of them (and whatever they pushed) by clearing these.
        .navigationDestination(isPresented: $showSearch) { searchDestination }
        .navigationDestination(isPresented: $showFriends) { MyFriendsView() }
        .navigationDestination(isPresented: $showProfile) { SocialProfileView() }
        .onAppear(perform: openFriendsIfRequested)
        .onChange(of: appState.pendingOpenFriends) { _, _ in openFriendsIfRequested() }
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Find friends")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let me = friends.myProfile {
                    Button {
                        showProfile = true
                    } label: {
                        AvatarView(profile: me, size: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your profile")
                }
            }
        }
    }

    private func openFriendsIfRequested() {
        guard appState.pendingOpenFriends else { return }
        appState.pendingOpenFriends = false
        showFriends = true
    }

    // One destination for the toolbar magnifier and the empty-state button.
    @ViewBuilder private var searchDestination: some View {
        UserSearchView()
    }
}
