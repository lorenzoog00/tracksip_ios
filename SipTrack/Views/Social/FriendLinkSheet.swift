import SwiftUI

/// Opened from a shared profile link: resolves the username and offers the right action.
struct FriendLinkSheet: View {
    let username: String

    @EnvironmentObject var friends: FriendsStore
    @Environment(\.dismiss) private var dismiss

    private enum Lookup: Equatable {
        case loading
        case notFound
        case failed
        case found(FriendProfile)
    }

    @State private var lookup: Lookup = .loading
    @State private var errorText: String?
    @StateObject private var coordinator = FriendActionCoordinator()

    private enum Relation { case me, friend, outgoing, incoming, stranger }

    /// Changes on the tap, before the server answers (`FriendsStore.pending`).
    private func relation(to profile: FriendProfile) -> Relation {
        if friends.myProfile?.uid == profile.uid { return .me }
        switch friends.rowState(for: profile.uid) {
        case .friend: return .friend
        case .accept: return .incoming
        case .pending: return .outgoing
        case .add: return .stranger
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    content
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.danger)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if case .found(let profile) = lookup, relation(to: profile) != .me, relation(to: profile) != .friend {
                        ReportBlockMenu(profile: profile, coordinator: coordinator)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .friendActionDialogs(coordinator)
        .onAppear {
            coordinator.errorHandler = { title, message in errorText = "\(title): \(message)" }
        }
        .task(id: username) { await resolve() }
        .onChange(of: friends.blocked.map(\.uid)) { _, ids in
            if case .found(let profile) = lookup, ids.contains(profile.uid) { dismiss() }
        }
    }

    @ViewBuilder private var content: some View {
        switch lookup {
        case .loading:
            ProgressView().tint(AppColors.accent)
        case .notFound:
            message("No one with that username")
        case .failed:
            VStack(spacing: 16) {
                message("Couldn't look that up. Check your connection and try again.")
                Button("Try again") { Task { await resolve() } }
                    .foregroundStyle(AppColors.accent)
            }
        case .found(let profile):
            VStack(spacing: 16) {
                AvatarView(profile: profile, size: 96)
                Text("@\(profile.username)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.text)
                action(for: profile)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder private func action(for profile: FriendProfile) -> some View {
        switch relation(to: profile) {
        case .me:
            message("That's your own profile")
        case .friend:
            message("You're already friends")
        case .outgoing:
            message("Request sent")
        case .incoming:
            primaryButton("Accept", for: profile, failure: "Couldn't accept request") {
                try await friends.respond(to: profile.uid, accept: true)
            }
        case .stranger:
            primaryButton("Add friend", for: profile, failure: "Couldn't send request") {
                try await friends.sendRequest(to: profile.uid)
            }
        }
    }

    /// The coordinator keeps a second tap out while `work` runs and puts a
    /// failure under the button (`errorHandler`); the store rolls the state back.
    private func primaryButton(
        _ title: String,
        for profile: FriendProfile,
        failure: String,
        _ work: @escaping () async throws -> Void
    ) -> some View {
        Button {
            errorText = nil
            coordinator.run(profile, failure: failure, work)
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(coordinator.isBusy(profile) || friends.pending.isPending(profile.uid))
        .padding(.top, 8)
    }

    private func resolve() async {
        lookup = .loading
        errorText = nil
        // Search may not return the caller, so answer for myself locally.
        if let me = friends.myProfile, me.username.lowercased() == username {
            lookup = .found(me)
            return
        }
        do {
            let found = try await friends.search(username)
            if Task.isCancelled { return }
            if let match = found.first(where: { $0.username.lowercased() == username }) {
                lookup = .found(match)
            } else {
                lookup = .notFound
            }
        } catch {
            if Task.isCancelled { return }
            lookup = .failed
            errorText = error.localizedDescription
        }
    }
}
