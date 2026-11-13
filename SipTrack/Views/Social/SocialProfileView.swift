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
                            // TODO(Task 13): replace with MyFriendsView.
                            SocialPlaceholderView(title: "My friends")
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
                }
                .padding(20)
            }
        }
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
