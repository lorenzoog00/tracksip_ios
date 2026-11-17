import SwiftUI
import PhotosUI

/// Claims a username (and optionally a photo) so the user can join the Friends tab.
/// In `.rename` mode it is pushed from the profile screen and dismisses on success.
struct ChooseUsernameView: View {
    enum Mode { case create, rename }

    var mode: Mode = .create

    @EnvironmentObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @FocusState private var focused: Bool

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._")

    private var isValid: Bool {
        (3...20).contains(username.count) && username.allSatisfy { Self.allowed.contains($0) }
    }

    /// Live hint under the field, mirroring the server rules.
    private var hint: String {
        if username.isEmpty { return "3-20 characters: lowercase letters, numbers, . and _" }
        if username.count < 3 { return "Too short. Use at least 3 characters." }
        if username.count > 20 { return "Too long. Use at most 20 characters." }
        if !username.allSatisfy({ Self.allowed.contains($0) }) {
            return "Only lowercase letters, numbers, . and _ are allowed."
        }
        return "Looks good."
    }

    private var hintColor: Color {
        username.isEmpty || isValid ? AppColors.textSecondary : AppColors.danger
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(mode == .create ? "Choose a username" : "Change username")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppColors.text)
                        Text("Friends find you by this name.")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 24)

                    if mode == .create {
                        photoPicker
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("@")
                                .foregroundStyle(AppColors.textSecondary)
                            TextField("username", text: $username)
                                .focused($focused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit { submit() }
                                .foregroundStyle(AppColors.text)
                        }
                        .font(.system(size: 18))
                        .padding(12)
                        .background(AppColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(hint)
                            .font(.system(size: 13))
                            .foregroundStyle(hintColor)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.danger)
                        }
                    }

                    Button(action: submit) {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.black)
                            } else {
                                Text(mode == .create ? "Continue" : "Save")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accent.opacity(isValid ? 1 : 0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!isValid || isSubmitting)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle(mode == .rename ? "Username" : "")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: username) { _, newValue in
            // Usernames are lowercase on the server; fold what the keyboard gives us.
            let folded = newValue.lowercased()
            if folded != newValue { username = folded }
            errorMessage = nil
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pickedImage = image
                } else {
                    showSocialNotice(title: "Photo unavailable", message: "That photo couldn't be loaded. Try another one.")
                }
                pickerItem = nil
            }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(AppColors.surface)
                    if let pickedImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())

                Text(pickedImage == nil ? "Add a photo (optional)" : "Change photo")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accent)
            }
        }
    }

    private func submit() {
        guard isValid, !isSubmitting else { return }
        focused = false
        isSubmitting = true
        errorMessage = nil
        let name = username
        let image = pickedImage
        Task {
            do {
                try await friends.claimUsername(name)
                if mode == .create, let image {
                    // The username is already claimed; a failed photo must not undo that.
                    do {
                        try await friends.setAvatar(image)
                    } catch {
                        showSocialNotice(
                            title: "Photo not uploaded",
                            message: "Username saved, but the photo couldn't be uploaded. Add it from your profile."
                        )
                    }
                }
                isSubmitting = false
                if mode == .rename { dismiss() }
                // In create mode the profile listener flips SocialRootView to the feed.
            } catch {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
