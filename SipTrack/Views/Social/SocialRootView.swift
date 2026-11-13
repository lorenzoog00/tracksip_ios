import SwiftUI

/// Stand-in for screens Tasks 12 and 13 build. Delete once they land.
struct SocialPlaceholderView: View {
    let title: String

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            Text(title)
                .foregroundStyle(AppColors.textSecondary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Social tab: pick a username first, then the friends feed.
struct SocialRootView: View {
    @EnvironmentObject var friends: FriendsStore
    @State private var showSearch = false

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

    // One destination for the toolbar magnifier and the empty-state button.
    @ViewBuilder private var searchDestination: some View {
        UserSearchView()
    }
}
