import SwiftUI

/// The Social tab: pick a username first, then the friends feed.
struct SocialRootView: View {
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var appState: AppState
    @State private var showSearch = false
    @State private var showFriends = false

    var body: some View {
        NavigationStack {
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
            }
        }
    }

    private var feed: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                if friends.incoming.count > 0 {
                    NavigationLink {
                        MyFriendsView()
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
                }
                FeedView(onAddFriend: { showSearch = true })
            }
        }
        .navigationDestination(isPresented: $showSearch) { searchDestination }
        .navigationDestination(isPresented: $showFriends) { MyFriendsView() }
        .onAppear(perform: openFriendsIfRequested)
        .onChange(of: appState.pendingOpenFriends) { _, _ in openFriendsIfRequested() }
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    searchDestination
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Find friends")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let me = friends.myProfile {
                    NavigationLink {
                        SocialProfileView()
                    } label: {
                        AvatarView(profile: me, size: 30)
                    }
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
