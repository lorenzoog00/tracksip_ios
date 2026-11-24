import Contacts
import MessageUI
import SwiftUI

/// Find people by username and send or accept friend requests. With nothing
/// typed it shows "You might know": contacts who are on TrackSip, friends of
/// friends, and contacts to invite. Contacts need a verified number on the
/// account and contacts permission; the server allows two checks a day, so the
/// last check is reused for 24 hours (`FriendsStore.cachedContactMatches`).
struct UserSearchView: View {
    @EnvironmentObject var friends: FriendsStore
    @EnvironmentObject var firebase: FirebaseManager

    @State private var query = ""
    @State private var results: [FriendProfile] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @StateObject private var coordinator = FriendActionCoordinator()
    @State private var suggestions: [PersonSuggestion] = []
    @State private var loadingSuggestions = true
    @State private var contacts: ContactsState = .idle
    /// The address book as read on this visit, for the Invite list. Kept in
    /// memory only; never saved.
    @State private var entries: [ContactEntry] = []
    /// Contacts to invite, sorted by name. Rebuilt when `entries` or the check change.
    @State private var invitable: [ContactEntry] = []
    /// The address book couldn't be read for a saved check's Invite list.
    @State private var contactsReadFailed = false
    /// Contact ids invited from this account in the last 7 days.
    @State private var invited: Set<String> = []
    @State private var inviteQuery = ""
    @State private var showAllInvites = false
    @State private var showAddPhone = false
    @State private var messageDraft: MessageDraft?
    @State private var shareDraft: ShareDraft?
    /// The person whose profile a row tap pushed.
    @State private var openedProfile: OpenedProfile?

    private enum ContactsState: Equatable {
        case idle, checking, denied
        case done(ContactMatchResult)
        /// Today's checks are used up and none of them is saved on this phone.
        case limitReached
        case failed(String)
    }

    private typealias RowState = PendingFriendActions.RowState

    /// An invite going out through the Messages composer.
    private struct MessageDraft: Identifiable {
        let id = UUID()
        let uid: String
        let contactID: String
        let recipient: String
        let body: String
    }

    /// An invite going out through the share sheet (no WhatsApp, no Messages).
    private struct ShareDraft: Identifiable {
        let id = UUID()
        let text: String
    }

    /// A profile opened from a row, with why they were suggested (nil from a search).
    private struct OpenedProfile {
        let profile: FriendProfile
        let reason: PersonSuggestion.Reason?
    }

    /// Invite rows shown before "Show all".
    private static let invitePageSize = 30

    private var cleaned: String {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.hasPrefix("@") { q.removeFirst() }
        return q
    }

    /// Changes on the tap, before the server answers (`FriendsStore.pending`).
    private func state(for profile: FriendProfile) -> RowState {
        friends.rowState(for: profile.uid)
    }

    /// Friends drop out of the suggestions only once the listener has them, so
    /// an accepted row shows "Friends" until then instead of vanishing on the tap.
    private func isFriend(_ profile: FriendProfile) -> Bool {
        friends.friends.contains { $0.uid == profile.uid }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            if cleaned.count < 2 {
                youMightKnow
            } else if isSearching && results.isEmpty {
                ProgressView().tint(AppColors.accent)
            } else if results.isEmpty {
                hint("No one found for \"\(cleaned)\".")
            } else {
                List {
                    ForEach(results, id: \.uid) { profile in
                        row(profile)
                            .listRowBackground(AppColors.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Find friends")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search @username")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .friendActionDialogs(coordinator)
        .sheet(isPresented: $showAddPhone) {
            AddPhoneView { added in
                showAddPhone = false
                guard added else { return }
                friends.clearContactCache()
                // The number is what the check needs; run it now (asking for
                // contacts first if it hasn't been asked yet).
                Task { await checkContacts() }
            }
        }
        .sheet(item: $messageDraft) { draft in
            MessageComposer(recipient: draft.recipient, body: draft.body) { result in
                messageDraft = nil
                if result == .sent { markInvited(draft.contactID, by: draft.uid) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $shareDraft) { draft in
            ShareSheet(items: [draft.text])
        }
        .navigationDestination(isPresented: openedProfileBinding) {
            if let openedProfile {
                FriendProfileView(profile: openedProfile.profile, suggestion: openedProfile.reason)
            }
        }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: firebase.phoneNumber) { _, phone in
            // Added, changed or removed (here or on another phone): nothing from
            // the old number's check stays on screen, and a new number shows its
            // own (saved check, else a new one when contacts are allowed). One
            // added in the sheet above is checked by the sheet's handler once it
            // closes; starting one here too could spend both of the day's checks.
            forgetContacts()
            if phone != nil, !showAddPhone {
                Task { await showContacts(refresh: false) }
            }
        }
        .onDisappear { searchTask?.cancel() }
        .task { await loadSuggestions(refresh: false) }
    }

    private var openedProfileBinding: Binding<Bool> {
        Binding(
            get: { openedProfile != nil },
            set: { if !$0 { openedProfile = nil } }
        )
    }

    // MARK: - You might know

    /// The check on screen, only while the account has a number.
    private var contactResult: ContactMatchResult? {
        guard firebase.phoneNumber != nil, case .done(let result) = contacts else { return nil }
        return result
    }

    private var contactMatches: [PersonSuggestion] {
        guard let result = contactResult else { return [] }
        let found = result.profiles.map { snapshot in
            PersonSuggestion(profile: snapshot.profile, reason: .contact)
        }
        return PersonSuggestion.visible(found, myUid: friends.currentUid, blocked: friends.blockedUidSet)
            .filter { !isFriend($0.profile) }
    }

    /// Friends of friends, minus anyone already listed from contacts or now a friend.
    private var mutualSuggestions: [PersonSuggestion] {
        let fromContacts = Set(contactMatches.map(\.id))
        return PersonSuggestion.visible(suggestions, myUid: friends.currentUid, blocked: friends.blockedUidSet)
            .filter { !fromContacts.contains($0.id) && !isFriend($0.profile) }
    }

    /// Only after a check: without it the list could invite people who already
    /// have TrackSip.
    private var showsInviteList: Bool {
        contactResult != nil && !invitable.isEmpty
    }

    /// A saved check is on screen but the address book couldn't be read, so
    /// there is no Invite list to show.
    private var showsContactsReadError: Bool {
        contactResult != nil && invitable.isEmpty && contactsReadFailed
    }

    private var filteredInvites: [ContactEntry] {
        let q = inviteQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return invitable }
        return invitable.filter { $0.name.localizedStandardContains(q) }
    }

    private var youMightKnow: some View {
        List {
            Section { contactsCard }
                .listRowBackground(AppColors.surface)

            if !contactMatches.isEmpty {
                Section {
                    ForEach(contactMatches) { suggestion in
                        row(suggestion.profile, subtitle: suggestion.subtitle, reason: suggestion.reason)
                    }
                } header: {
                    sectionHeader("In your contacts")
                }
                .listRowBackground(AppColors.surface)
            }

            Section {
                if loadingSuggestions && suggestions.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().tint(AppColors.accent)
                        Spacer()
                    }
                } else if mutualSuggestions.isEmpty {
                    Text("When your friends add friends, people you might know show up here.")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(mutualSuggestions) { suggestion in
                        row(suggestion.profile, subtitle: suggestion.subtitle, reason: suggestion.reason)
                    }
                }
            } header: {
                sectionHeader("You might know")
            }
            .listRowBackground(AppColors.surface)

            if showsInviteList || showsContactsReadError {
                Section {
                    if showsInviteList {
                        // Filtered once per render, here, and handed down.
                        inviteRows(filteredInvites)
                    } else {
                        Text("Couldn't read your contacts.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } header: {
                    sectionHeader("Invite to TrackSip")
                }
                .listRowBackground(AppColors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        // Pulling runs a new contacts check, which spends one of the day's two.
        .refreshable { await loadSuggestions(refresh: true) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private var contactsCard: some View {
        if firebase.phoneNumber == nil {
            Button {
                showAddPhone = true
            } label: {
                cardLabel("Add your number to find friends from your contacts", subtitle: nil)
            }
            .buttonStyle(.plain)
        } else {
            switch contacts {
            case .idle, .failed:
                Button {
                    Task { await checkContacts() }
                } label: {
                    cardLabel("Find friends from your contacts",
                              subtitle: contactsFailureText ?? "Only phone numbers are checked, and nothing is stored on our servers.",
                              subtitleIsError: contactsFailureText != nil)
                }
                .buttonStyle(.plain)
            case .checking:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppColors.accent)
                        .frame(width: 40)
                    Text("Checking your contacts...")
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.textSecondary)
                }
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Contacts are off for TrackSip")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                    Text("Turn them on in Settings to find friends who already use it.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                            .font(.system(size: 15, weight: .semibold))
                            .tint(AppColors.accent)
                    }
                }
            case .done(let result):
                statusRow(icon: "checkmark.circle.fill", tint: AppColors.success,
                          text: checkedText(result))
            case .limitReached:
                statusRow(icon: "clock", tint: AppColors.textSecondary,
                          text: "You've already checked today. Your results will be here tomorrow.")
            }
        }
    }

    private func cardLabel(_ title: LocalizedStringKey, subtitle: String?, subtitleIsError: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.accent)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(subtitleIsError ? AppColors.danger : AppColors.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func statusRow(icon: String, tint: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    /// "Invite them below" only when there is an Invite list below.
    private func checkedText(_ result: ContactMatchResult) -> LocalizedStringKey {
        guard result.profiles.isEmpty && result.onTrackSip.isEmpty else { return "Contacts checked" }
        return showsInviteList
            ? "None of your contacts are on TrackSip yet. Invite them below."
            : "None of your contacts are on TrackSip yet."
    }

    private var contactsFailureText: String? {
        if case .failed(let message) = contacts { return message }
        return nil
    }

    // MARK: - Invite list

    /// `invites` is `filteredInvites`, computed once by the caller for this render.
    @ViewBuilder
    private func inviteRows(_ invites: [ContactEntry]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)
            TextField("Search contacts", text: $inviteQuery)
                .foregroundStyle(AppColors.text)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        if invites.isEmpty {
            Text("No contacts match \"\(inviteQuery.trimmingCharacters(in: .whitespacesAndNewlines))\".")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
        } else {
            let shown: [ContactEntry] = showAllInvites ? invites : Array(invites.prefix(Self.invitePageSize))
            ForEach(shown) { entry in
                inviteRow(entry)
            }
            if !showAllInvites && invites.count > Self.invitePageSize {
                Button {
                    showAllInvites = true
                } label: {
                    Text("Show all (\(invites.count))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func inviteRow(_ entry: ContactEntry) -> some View {
        let isInvited = invited.contains(entry.id)
        // The invite text carries my username; without one there is nothing to send.
        let hasUsername = friends.myProfile?.username != nil
        return HStack(spacing: 12) {
            Text(Self.initial(of: entry.name))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.text)
                .frame(width: 40, height: 40)
                .background(AppColors.border)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(entry.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
            Spacer()
            Button {
                invite(entry)
            } label: {
                Text(isInvited ? "Invited" : "Invite")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(isInvited ? AppColors.textSecondary : Color.black)
                    .background(isInvited ? AppColors.border : AppColors.accent.opacity(hasUsername ? 1 : 0.4))
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
            .disabled(isInvited || !hasUsername)
        }
    }

    /// The first letter or digit of a name, for its round placeholder.
    private static func initial(of name: String) -> String {
        guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "#" }
        return String(first).uppercased()
    }

    /// WhatsApp when it's installed, else the Messages composer, else the share
    /// sheet, with the same text. Invited is set once WhatsApp opens (iOS can't
    /// confirm a WhatsApp send) or the composer reports sent.
    private func invite(_ entry: ContactEntry) {
        guard let uid = friends.currentUid,
              let username = friends.myProfile?.username,
              let phone = entry.phones.first else { return }
        let spanish = Locale.preferredLanguages.first?.hasPrefix("es") ?? false
        let message = Invite.message(username: username, spanish: spanish)
        if let probe = URL(string: "whatsapp://"), UIApplication.shared.canOpenURL(probe),
           let url = Invite.whatsAppURL(phone: phone, message: message) {
            Task {
                if await UIApplication.shared.open(url) {
                    markInvited(entry.id, by: uid)
                }
            }
        } else if MFMessageComposeViewController.canSendText() {
            messageDraft = MessageDraft(uid: uid, contactID: entry.id, recipient: phone, body: message)
        } else {
            shareDraft = ShareDraft(text: message)
        }
    }

    /// Nothing is marked if another account is signed in by the time the invite went out.
    private func markInvited(_ contactID: String, by uid: String) {
        guard uid == friends.currentUid else { return }
        Invite.markInvited(contactID: contactID, uid: uid)
        invited.insert(contactID)
    }

    // MARK: - Loading

    private func loadSuggestions(refresh: Bool) async {
        loadingSuggestions = true
        let contactsTask = Task {
            // The first load of each visit re-reads the number: it may have been
            // added, changed or removed on another phone. A change lands in the
            // `firebase.phoneNumber` handler, which clears the old number's check
            // and shows the new one's.
            if !refresh, friends.cachedContactMatches() == nil {
                // Nothing saved, so showing contacts means a new check: re-read
                // first, or a number changed elsewhere would spend one check on
                // the old number and another on the new.
                let before = firebase.phoneNumber
                await firebase.refreshPhoneNumber()
                // Changed: the handler owns it. Showing here too could set
                // .checking before the handler's reset, which would then start
                // a second check.
                guard firebase.phoneNumber == before else { return }
                await showContacts(refresh: false)
            } else {
                // A fresh saved check shows without waiting for the network (and
                // a tap on the card meanwhile can't spend a check), then the re-read.
                await showContacts(refresh: refresh)
                if !refresh { await firebase.refreshPhoneNumber() }
            }
        }
        do {
            suggestions = try await friends.suggestions()
        } catch {
            // Suggestions are a nicety; the username search still works.
            suggestions = []
        }
        loadingSuggestions = false
        // Pull to refresh stays up until the new contacts check is in too.
        if refresh { await contactsTask.value }
    }

    /// Fills the contacts sections: the saved check while it is fresh (no server
    /// call), else a new check when contacts are already allowed, as before.
    /// `refresh` (pull to refresh) always checks, spending one of the day's two.
    private func showContacts(refresh: Bool) async {
        guard let phone = firebase.phoneNumber else {
            forgetContacts()
            return
        }
        // Not asked yet, or turned off: the card asks or explains on a tap.
        guard ContactPhones.isAllowed else { return }
        if !refresh, let cached = friends.cachedContactMatches() {
            contacts = .done(cached)
            await loadEntries(ownPhone: phone)
        } else if refresh || contacts == .idle {
            await checkContacts()
        }
    }

    private func checkContacts() async {
        guard contacts != .checking, let phone = firebase.phoneNumber else { return }
        let uid = friends.currentUid
        // Signed out, switched account or changed number since this check began:
        // the answer belongs to no one on screen. The `firebase.phoneNumber`
        // handler resets the card (and may start a new check).
        func isStale() -> Bool {
            friends.currentUid != uid || firebase.phoneNumber != phone
        }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .denied, .restricted:
            contacts = .denied
            return
        case .notDetermined:
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            guard !isStale() else { return }
            guard granted else {
                contacts = .denied
                return
            }
        default:
            break
        }
        let shown = contacts
        contacts = .checking
        // A stale answer is dropped. A changed number's handler has reset the
        // card; with the same number (only the account changed) put back what
        // was showing, or the card would stay on "Checking…".
        func droppedAsStale() -> Bool {
            guard isStale() else { return false }
            if contacts == .checking, firebase.phoneNumber == phone { contacts = shown }
            return true
        }
        do {
            let read = try await Self.readContacts(ownPhone: phone)
            if droppedAsStale() { return }
            entries = read
            contactsReadFailed = false
            let phones = ContactPhones.phonesToCheck(read, ownPhone: phone)
            let result: ContactMatchResult
            if phones.isEmpty {
                // No numbers to ask about: don't spend a check on nothing.
                result = ContactMatchResult(profiles: [], onTrackSip: [])
            } else {
                result = try await friends.contactMatches(phones: phones)
                if droppedAsStale() { return }
            }
            contacts = .done(result)
        } catch let error where FirebaseManager.isContactCheckLimit(error) {
            if droppedAsStale() { return }
            // Never the server's own sentence: the saved check, else ours.
            if let cached = friends.cachedContactMatches() {
                contacts = .done(cached)
            } else if case .done = shown {
                contacts = shown
            } else {
                contacts = .limitReached
            }
        } catch {
            if droppedAsStale() { return }
            if case .done = shown {
                // A failed refresh keeps what was on screen.
                contacts = shown
                showSocialNotice(title: "Couldn't check your contacts", message: error.localizedDescription)
            } else {
                contacts = .failed(error.localizedDescription)
            }
        }
        rebuildInvitable()
    }

    /// Reads the address book for the Invite list when showing a saved check. No
    /// server call. A failed read keeps the saved check and says so in the Invite
    /// section. Dropped if the number changed or was removed meanwhile.
    private func loadEntries(ownPhone: String) async {
        if entries.isEmpty {
            do {
                let read = try await Self.readContacts(ownPhone: ownPhone)
                guard firebase.phoneNumber == ownPhone else { return }
                entries = read
                contactsReadFailed = false
            } catch {
                guard firebase.phoneNumber == ownPhone else { return }
                contactsReadFailed = true
            }
        }
        rebuildInvitable()
    }

    /// The address book as entries, read off the main thread (enumeration
    /// blocks). Numbers saved without a country code count as numbers of the
    /// user's own country.
    private static func readContacts(ownPhone: String) async throws -> [ContactEntry] {
        let region = PhoneNumbers.region(ofE164: ownPhone) ?? PhoneNumbers.defaultRegion
        return try await Task.detached(priority: .userInitiated) {
            try ContactPhones.load(defaultRegion: region)
        }.value
    }

    private func rebuildInvitable() {
        guard case .done(let result) = contacts, let phone = firebase.phoneNumber else {
            invitable = []
            return
        }
        invitable = ContactPhones.invitable(entries, onTrackSip: result.onTrackSip, ownPhone: phone)
        invited = friends.currentUid.map { uid in Invite.invitedContactIDs(uid: uid, now: Date()) } ?? []
    }

    /// No number, or a different one: nothing read from contacts for the old one
    /// stays in memory or on screen.
    private func forgetContacts() {
        contacts = .idle
        entries = []
        invitable = []
        invited = []
        inviteQuery = ""
        showAllInvites = false
        contactsReadFailed = false
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    /// The avatar and name open their profile (`reason` feeds its mutual-friends line);
    /// the Add / Accept button and the ⋯ menu keep their own taps.
    private func row(_ profile: FriendProfile, subtitle: String? = nil, reason: PersonSuggestion.Reason? = nil) -> some View {
        HStack(spacing: 12) {
            Button {
                openedProfile = OpenedProfile(profile: profile, reason: reason)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(profile: profile, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        ProfileNameLabel(profile: profile)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    // Says the row opens something; the hint says what.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            // Borderless: only this part of the row opens the profile, so the button
            // and the ⋯ menu keep their own taps.
            .buttonStyle(.borderless)
            .accessibilityHint("Opens their profile")
            actionButton(profile)
            ReportBlockMenu(profile: profile, coordinator: coordinator)
        }
    }

    @ViewBuilder
    private func actionButton(_ profile: FriendProfile) -> some View {
        let rowState = state(for: profile)
        // Held from the tap until the listener shows the change, so no second tap.
        let inFlight = coordinator.isBusy(profile) || friends.pending.isPending(profile.uid)
        Button {
            act(profile, rowState)
        } label: {
            Text(title(rowState))
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(rowState == .add || rowState == .accept ? Color.black : AppColors.textSecondary)
                .background(rowState == .add || rowState == .accept ? AppColors.accent : AppColors.border)
                .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(inFlight || rowState == .pending || rowState == .friend)
    }

    private func title(_ s: RowState) -> String {
        switch s {
        case .add: return "Add"
        case .pending: return "Pending"
        case .friend: return "Friends"
        case .accept: return "Accept"
        }
    }

    /// The row flips at once (`FriendsStore.pending`); a failure flips it back and
    /// the coordinator shows the error.
    private func act(_ profile: FriendProfile, _ rowState: RowState) {
        guard rowState == .add || rowState == .accept else { return }
        coordinator.run(profile, failure: "Couldn't update request") {
            if rowState == .add {
                try await friends.sendRequest(to: profile.uid)
            } else {
                try await friends.respond(to: profile.uid, accept: true)
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = cleaned
        guard q.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            do {
                let found = try await friends.search(q)
                if Task.isCancelled { return }
                results = found
            } catch {
                if Task.isCancelled { return }
                results = []
                showSocialNotice(title: "Search failed", message: error.localizedDescription)
            }
            isSearching = false
        }
    }
}
