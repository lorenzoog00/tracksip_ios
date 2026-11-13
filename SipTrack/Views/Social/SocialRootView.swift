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

    var body: some View {
        NavigationStack {
            if friends.myProfile == nil {
                ChooseUsernameView(mode: .create)
            } else {
                feed
            }
        }
    }

    private var feed: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            // TODO(Task 12): replace with FeedView (and FriendNightView destinations).
            Text("Friends feed")
                .foregroundStyle(AppColors.textSecondary)
        }
        .navigationTitle("Social")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    // TODO(Task 13): replace with UserSearchView.
                    SocialPlaceholderView(title: "Find friends")
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
}
