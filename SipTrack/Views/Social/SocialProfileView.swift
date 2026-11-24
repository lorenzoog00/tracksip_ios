import SwiftUI
import PhotosUI

/// My social profile: photo, name, username, the incognito default, the stats switch
/// and the friends list.
struct SocialProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var firebase: FirebaseManager

    @State private var showAddPhone = false
    @State private var confirmRemovePhone = false
    @State private var isRemovingPhone = false
    @State private var phoneError: String?
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
    /// The Name field as typed. It follows the saved name while not being edited.
    @State private var nameDraft = ""
    @State private var isSavingName = false
    /// The server's reason for refusing a name, shown under the field.
    @State private var nameError: String?
    @FocusState private var nameFocused: Bool

    /// The server's limit, counted here in characters as typed.
    private static let nameLimit = 30

    private var savedName: String { friends.myProfile?.name ?? "" }

    private var trimmedNameDraft: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameChanged: Bool { trimmedNameDraft != savedName }

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

    /// Off deletes the stats doc friends read; on publishes it. Saved on this phone.
    private var shareStatsBinding: Binding<Bool> {
        Binding(
            get: { appState.shareStatsWithFriends },
            set: { appState.setShareStatsWithFriends($0) }
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

                        nameField

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

                        Toggle(isOn: shareStatsBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show my stats to friends")
                                    .foregroundStyle(AppColors.text)
                                Text("Nights logged, 90-day averages and your favorite drink. Incognito nights never count.")
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

                    phoneSection

                    notificationsSection
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task { await loadNotificationPrefs() }
        .onChange(of: friends.myProfile?.name) { _, name in
            // Saved elsewhere (or loaded late): show it, unless it's being typed over.
            if !nameFocused && !isSavingName { nameDraft = name ?? "" }
        }
        .onChange(of: nameDraft) { _, typed in
            if typed.count > Self.nameLimit { nameDraft = String(typed.prefix(Self.nameLimit)) }
            nameError = nil
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
        .sheet(isPresented: $showAddPhone) {
            AddPhoneView { added in
                showAddPhone = false
                // Answered here, so the feed doesn't ask again right after.
                if let uid = firebase.currentUserId() {
                    PhonePrompt.markDismissed(uid: uid)
                }
                if added { friends.clearContactCache() }
            }
        }
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

    // MARK: - Name

    /// Shown above the @username in friends' lists and search; blank shows the
    /// @username alone. Saved on Done or with Save, which shows only once the
    /// name differs from the saved one.
    private var nameField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                TextField("Your name", text: $nameDraft)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { saveName() }
                    .foregroundStyle(AppColors.text)
                    .accessibilityLabel("Name")
                if isSavingName {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.accent)
                } else if nameChanged {
                    Button("Save") { saveName() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let nameError {
                Text(nameError)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            if !nameFocused && !isSavingName { nameDraft = savedName }
        }
    }

    private func saveName() {
        guard !isSavingName else { return }
        let name = trimmedNameDraft
        nameFocused = false
        guard name != savedName else {
            // Nothing new; just drop stray spaces.
            if nameDraft != name { nameDraft = name }
            return
        }
        isSavingName = true
        nameError = nil
        Task {
            do {
                let saved = try await friends.setDisplayName(name)
                // Typed over while saving: keep the newer text (Save shows again).
                if trimmedNameDraft == name { nameDraft = saved ?? "" }
            } catch {
                // The server's own copy: "Names can be up to 30 characters." and the like.
                nameError = error.localizedDescription
            }
            isSavingName = false
        }
    }

    // MARK: - Phone number

    /// Only ever shown here, on the owner's own profile.
    private var phoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phone number")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                if let number = firebase.phoneNumber {
                    HStack {
                        Text(PhoneNumbers.formatted(number))
                            .foregroundStyle(AppColors.text)
                        Spacer()
                        if isRemovingPhone {
                            ProgressView().tint(AppColors.accent)
                        }
                    }
                    .padding(16)

                    Divider().overlay(AppColors.border)

                    HStack(spacing: 0) {
                        Button {
                            phoneError = nil
                            showAddPhone = true
                        } label: {
                            Text("Change")
                                .foregroundStyle(AppColors.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }

                        Divider().overlay(AppColors.border)

                        Button {
                            phoneError = nil
                            confirmRemovePhone = true
                        } label: {
                            Text("Remove")
                                .foregroundStyle(AppColors.danger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(isRemovingPhone)
                } else {
                    Button {
                        phoneError = nil
                        showAddPhone = true
                    } label: {
                        HStack {
                            Text("Add your number")
                                .foregroundStyle(AppColors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                }
            }
            .font(.system(size: 16))
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .confirmationDialog("Remove your number?", isPresented: $confirmRemovePhone, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removePhone() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Friends won't find you from their contacts.")
            }

            if let phoneError {
                Text(phoneError)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.danger)
                    .padding(.leading, 4)
            } else {
                Text("Never shown to anyone. It lets friends find you from their contacts.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.leading, 4)
            }
        }
    }

    private func removePhone() {
        guard !isRemovingPhone else { return }
        isRemovingPhone = true
        phoneError = nil
        Task {
            do {
                try await firebase.removePhoneNumber()
                friends.clearContactCache()
            } catch {
                phoneError = FirebaseManager.phoneErrorText(error)
            }
            isRemovingPhone = false
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
