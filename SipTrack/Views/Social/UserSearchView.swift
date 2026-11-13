import SwiftUI

/// Find people by username and send or accept friend requests.
struct UserSearchView: View {
    @EnvironmentObject var friends: FriendsStore

    @State private var query = ""
    @State private var results: [FriendProfile] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    /// Requests sent from this screen, so the button flips before the Firestore listener catches up.
    @State private var sent: Set<String> = []
    @State private var busy: Set<String> = []

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
                hint("Type at least 2 characters of a username.")
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
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(32)
    }

    private func row(_ profile: FriendProfile) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            Text("@\(profile.username)")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.text)
            Spacer()
            actionButton(profile)
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
