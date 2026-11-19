import SwiftUI
import PhotosUI

/// My social profile: photo, username, the incognito default and the friends list.
struct SocialProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var friends: FriendsStore

    @State private var pickerItem: PhotosPickerItem?
    @State private var showAvatarOptions = false
    @State private var showPicker = false
    @State private var errorMessage: String?
    @State private var isUpdatingAvatar = false
    /// `notification_prefs/{uid}`; on until loaded, and the switches stay disabled
    /// until then so a stale "on" is never written over a saved "off".
    @State private var notifyReactions = true
    @State private var notifyComments = true
    @State private var notifyReplies = true
    @State private var notificationPrefsLoaded = false

    private var incognitoBinding: Binding<Bool> {
        Binding(
            get: { appState.userProfile.incognitoByDefault },
            set: { newValue in
                var profile = appState.userProfile
                profile.incognitoByDefault = newValue
                appState.updateUserProfile(profile)
            }
        )
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if let me = friends.myProfile {
                        Button { showAvatarOptions = true } label: {
                            ZStack {
                                AvatarView(profile: me, size: 96)
                                if isUpdatingAvatar {
                                    Circle().fill(AppColors.overlay).frame(width: 96, height: 96)
                                    ProgressView().tint(.white)
                                }
                            }
                        }
                        .disabled(isUpdatingAvatar)

                        NavigationLink {
                            ChooseUsernameView(mode: .rename)
                        } label: {
                            HStack(spacing: 6) {
                                Text("@\(me.username)")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(AppColors.text)
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.danger)
                    }

                    if let me = friends.myProfile {
                        ShareLink(
                            item: "Add me on TrackSip: @\(me.username) \(FriendLink.shareURL(for: me.username).absoluteString)"
                        ) {
                            Label("Share profile", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    VStack(spacing: 0) {
                        Toggle(isOn: incognitoBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Incognito by default")
                                    .foregroundStyle(AppColors.text)
                                Text("New nights are hidden from friends unless you turn it off.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.accent)
                        .padding(16)

                        Divider().overlay(AppColors.border)

                        NavigationLink {
                            MyFriendsView()
                        } label: {
                            HStack {
                                Text("My friends")
                                    .foregroundStyle(AppColors.text)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .padding(16)
                        }
                    }
                    .font(.system(size: 16))
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    notificationsSection
                }
                .padding(20)
            }
        }
        .task { await loadNotificationPrefs() }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Profile photo", isPresented: $showAvatarOptions) {
            Button("Choose photo") { showPicker = true }
            if friends.myProfile?.photoURL != nil {
                Button("Remove photo", role: .destructive) { updateAvatar(nil) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    updateAvatar(image)
                } else {
                    showSocialNotice(title: "Photo unavailable", message: "That photo couldn't be loaded. Try another one.")
                }
            }
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                notificationToggle("Reactions on your night", isOn: prefBinding("reactions", $notifyReactions))
                Divider().overlay(AppColors.border)
                notificationToggle("Comments on your night", isOn: prefBinding("comments", $notifyComments))
                Divider().overlay(AppColors.border)
                notificationToggle("Replies and mentions", isOn: prefBinding("replies", $notifyReplies))
            }
            .font(.system(size: 16))
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(!notificationPrefsLoaded)
        }
    }

    private func notificationToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .foregroundStyle(AppColors.text)
        }
        .tint(AppColors.accent)
        .padding(16)
    }

    /// Optimistic: flips at once, saves one key with merge, and flips back with a
    /// notice if the save fails (unless the user has flipped it again since).
    private func prefBinding(_ key: String, _ value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                Task {
                    do {
                        try await FirebaseManager.shared.setNotificationPref(key, on: newValue)
                    } catch {
                        if value.wrappedValue == newValue { value.wrappedValue = !newValue }
                        showSocialNotice(title: "Couldn't save", message: error.localizedDescription)
                    }
                }
            }
        )
    }

    private func loadNotificationPrefs() async {
        guard let prefs = try? await FirebaseManager.shared.notificationPrefs() else { return }
        notifyReactions = prefs.reactions
        notifyComments = prefs.comments
        notifyReplies = prefs.replies
        notificationPrefsLoaded = true
    }

    private func updateAvatar(_ image: UIImage?) {
        isUpdatingAvatar = true
        errorMessage = nil
        Task {
            do {
                try await friends.setAvatar(image)
            } catch {
                errorMessage = error.localizedDescription
            }
            isUpdatingAvatar = false
        }
    }
}
