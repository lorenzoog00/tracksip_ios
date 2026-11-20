import Contacts
import SwiftUI

/// Find people by username and send or accept friend requests. With nothing
/// typed it shows "You might know": friends of friends, and, once allowed,
/// contacts who are on TrackSip.
struct UserSearchView: View {
    @EnvironmentObject var friends: FriendsStore

    @State private var query = ""
    @State private var results: [FriendProfile] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    /// Requests sent from this screen, so the button flips before the Firestore listener catches up.
    @State private var sent: Set<String> = []
    @StateObject private var coordinator = FriendActionCoordinator()
    @State private var busy: Set<String> = []
    @State private var suggestions: [PersonSuggestion] = []
    @State private var loadingSuggestions = true
    @State private var contacts: ContactsState = .idle

    private enum ContactsState: Equatable {
        case idle, checking, denied
        case done([PersonSuggestion])
        case failed(String)
    }

    private enum RowState { case add, pending, friend, accept }

    private var cleaned: String {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.hasPrefix("@") { q.removeFirst() }
        return q
    }

    private func state(for profile: FriendProfile) -> RowState {
        if friends.friends.contains(where: { $0.uid == profile.uid }) { return .friend }
        if friends.incoming.contains(where: { $0.uid == profile.uid }) { return .accept }
        if sent.contains(profile.uid) || friends.outgoing.contains(where: { $0.uid == profile.uid }) { return .pending }
        return .add
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
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: friends.outgoing.map(\.uid)) { _, ids in
            // The snapshot has arrived; Pending now comes from `outgoing`, so a later
            // cancel or decline must not leave a stale "Pending" behind.
            sent.subtract(ids)
        }
        .onDisappear { searchTask?.cancel() }
        .task { await loadSuggestions() }
    }

    // MARK: - You might know

    private var contactMatches: [PersonSuggestion] {
        guard case .done(let found) = contacts else { return [] }
        return PersonSuggestion.visible(found, myUid: friends.currentUid, blocked: friends.blockedUidSet)
            .filter { state(for: $0.profile) != .friend }
    }

    /// Friends of friends, minus anyone already listed from contacts or now a friend.
    private var mutualSuggestions: [PersonSuggestion] {
        let fromContacts = Set(contactMatches.map(\.id))
        return PersonSuggestion.visible(suggestions, myUid: friends.currentUid, blocked: friends.blockedUidSet)
            .filter { !fromContacts.contains($0.id) && state(for: $0.profile) != .friend }
    }

    private var youMightKnow: some View {
        List {
            Section { contactsCard }
                .listRowBackground(AppColors.surface)

            if !contactMatches.isEmpty {
                Section {
                    ForEach(contactMatches) { suggestion in
                        row(suggestion.profile, subtitle: suggestion.subtitle)
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
                        row(suggestion.profile, subtitle: suggestion.subtitle)
                    }
                }
            } header: {
                sectionHeader("You might know")
            }
            .listRowBackground(AppColors.surface)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await loadSuggestions() }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private var contactsCard: some View {
        switch contacts {
        case .idle, .failed:
            Button {
                Task { await checkContacts() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 40)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Find friends from your contacts")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        Text(contactsFailureText ?? "Only email addresses are checked, and nothing is saved.")
                            .font(.system(size: 13))
                            .foregroundStyle(contactsFailureText == nil ? AppColors.textSecondary : AppColors.danger)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
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
                Text("Contacts are off for Tracksip")
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
        case .done(let found):
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.success)
                    .frame(width: 40)
                    .accessibilityHidden(true)
                Text(found.isEmpty ? "None of your contacts are on Tracksip Social yet." : "Contacts checked")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var contactsFailureText: String? {
        if case .failed(let message) = contacts { return message }
        return nil
    }

    private func loadSuggestions() async {
        loadingSuggestions = true
        defer { loadingSuggestions = false }
        // One contacts check per session and account: the server allows two a day.
        if let cached = friends.cachedContactMatches() {
            contacts = .done(cached)
        } else if contacts == .idle && ContactEmails.isAllowed {
            // Allowed on an earlier visit: check again without asking for a tap.
            Task { await checkContacts() }
        }
        do {
            suggestions = try await friends.suggestions()
        } catch {
            // Suggestions are a nicety; the username search still works.
            suggestions = []
        }
    }

    private func checkContacts() async {
        guard contacts != .checking else { return }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .denied, .restricted:
            contacts = .denied
            return
        case .notDetermined:
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            guard granted else {
                contacts = .denied
                return
            }
        default:
            break
        }
        contacts = .checking
        do {
            let emails = try await Task.detached(priority: .userInitiated) {
                try ContactEmails.load()
            }.value
            let found = emails.isEmpty ? [] : try await friends.contactMatches(emails: emails)
            contacts = .done(found)
        } catch {
            contacts = .failed(error.localizedDescription)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    private func row(_ profile: FriendProfile, subtitle: String? = nil) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(profile.username)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            actionButton(profile)
            ReportBlockMenu(profile: profile, coordinator: coordinator)
        }
    }

    @ViewBuilder
    private func actionButton(_ profile: FriendProfile) -> some View {
        let rowState = state(for: profile)
        let inFlight = busy.contains(profile.uid)
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

    private func act(_ profile: FriendProfile, _ rowState: RowState) {
        guard rowState == .add || rowState == .accept else { return }
        busy.insert(profile.uid)
        Task {
            do {
                if rowState == .add {
                    try await friends.sendRequest(to: profile.uid)
                    sent.insert(profile.uid)
                } else {
                    try await friends.respond(to: profile.uid, accept: true)
                }
            } catch {
                showSocialNotice(title: "Couldn't update request", message: error.localizedDescription)
            }
            busy.remove(profile.uid)
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

/// The email addresses in the address book, or in the contacts the user chose
/// to share (limited access). Load off the main thread: enumeration blocks.
enum ContactEmails {
    /// The server takes at most this many per check (CONTACT_EMAILS_MAX in social.js).
    nonisolated static let limit = 500

    /// Full or limited access already granted.
    static var isAllowed: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return true
        default: return false
        }
    }

    nonisolated static func load() throws -> [String] {
        let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
        var seen = Set<String>()
        var emails: [String] = []
        try CNContactStore().enumerateContacts(with: request) { contact, stop in
            for address in contact.emailAddresses {
                let email = (address.value as String).trimmingCharacters(in: .whitespaces).lowercased()
                if !email.isEmpty, seen.insert(email).inserted { emails.append(email) }
                if emails.count >= limit {
                    stop.pointee = true
                    return
                }
            }
        }
        return emails
    }
}
