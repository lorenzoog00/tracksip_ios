import SwiftUI

/// Requests, friends and blocked people, with the actions to manage them.
struct MyFriendsView: View {
    @EnvironmentObject var friends: FriendsStore

    @State private var busy: Set<String> = []
    @State private var removeTarget: FriendProfile?
    @State private var blockTarget: FriendProfile?
    @State private var reportTarget: FriendProfile?
    @State private var thanksTarget: FriendProfile?
    @State private var blockedExpanded = false

    private func isLive(_ profile: FriendProfile) -> Bool {
        let now = Date()
        return friends.feed.contains { $0.id == profile.uid && $0.night.isLive(now: now) }
    }

    private func flag(_ target: Binding<FriendProfile?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            List {
                Section {
                    NavigationLink {
                        UserSearchView()
                    } label: {
                        Label("Find friends", systemImage: "magnifyingglass")
                            .foregroundStyle(AppColors.text)
                    }
                    .listRowBackground(AppColors.surface)
                }

                if !friends.incoming.isEmpty {
                    Section("Requests") {
                        ForEach(friends.incoming, id: \.uid) { profile in
                            requestRow(profile)
                                .listRowBackground(AppColors.surface)
                        }
                    }
                }

                Section("Friends") {
                    if friends.friends.isEmpty {
                        Text("No friends yet. Find someone to add.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .listRowBackground(AppColors.surface)
                    }
                    ForEach(friends.friends, id: \.uid) { profile in
                        friendRow(profile)
                            .listRowBackground(AppColors.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Remove", role: .destructive) { removeTarget = profile }
                                    .disabled(busy.contains(profile.uid))
                            }
                    }
                }

                if !friends.blocked.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $blockedExpanded) {
                            ForEach(friends.blocked, id: \.uid) { profile in
                                blockedRow(profile)
                            }
                        } label: {
                            Text("Blocked (\(friends.blocked.count))")
                                .foregroundStyle(AppColors.text)
                        }
                        .tint(AppColors.textSecondary)
                        .listRowBackground(AppColors.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("My friends")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Remove @\(removeTarget?.username ?? "")?",
            isPresented: flag($removeTarget),
            presenting: removeTarget
        ) { profile in
            Button("Remove", role: .destructive) {
                run(profile, failure: "Couldn't remove friend") { try await friends.remove(profile.uid) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Block @\(blockTarget?.username ?? "")?",
            isPresented: flag($blockTarget),
            presenting: blockTarget
        ) { profile in
            Button("Block", role: .destructive) {
                run(profile, failure: "Couldn't block") { try await friends.block(profile.uid) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { profile in
            Text("@\(profile.username) won't be able to find you or send you requests. They'll also be removed from your friends.")
        }
        .confirmationDialog(
            "Report @\(reportTarget?.username ?? "")",
            isPresented: flag($reportTarget),
            titleVisibility: .visible,
            presenting: reportTarget
        ) { profile in
            Button("Username") { report(profile, .username) }
            Button("Photo") { report(profile, .photo) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Thanks — we'll review it.",
            isPresented: flag($thanksTarget),
            presenting: thanksTarget
        ) { profile in
            Button("Block @\(profile.username)", role: .destructive) {
                run(profile, failure: "Couldn't block") { try await friends.block(profile.uid) }
            }
            Button("Done", role: .cancel) {}
        }
    }

    // MARK: - Rows

    private func requestRow(_ profile: FriendProfile) -> some View {
        let disabled = busy.contains(profile.uid)
        return HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            Text("@\(profile.username)")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.text)
            Spacer()
            Button {
                run(profile, failure: "Couldn't accept request") { try await friends.respond(to: profile.uid, accept: true) }
            } label: {
                Text("Accept")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(Color.black)
                    .background(AppColors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.borderless)
            .disabled(disabled)
            Button {
                run(profile, failure: "Couldn't decline request") { try await friends.respond(to: profile.uid, accept: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(8)
            }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .accessibilityLabel("Decline")
        }
    }

    private func friendRow(_ profile: FriendProfile) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            Text("@\(profile.username)")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.text)
            if isLive(profile) {
                Circle()
                    .fill(AppColors.success)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Live now")
            }
            Spacer()
            Menu {
                Button("Remove") { removeTarget = profile }
                Button("Block", role: .destructive) { blockTarget = profile }
                Button("Report") { reportTarget = profile }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .disabled(busy.contains(profile.uid))
            .accessibilityLabel("More options")
        }
    }

    private func blockedRow(_ profile: FriendProfile) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: profile, size: 32)
            Text("@\(profile.username)")
                .foregroundStyle(AppColors.text)
            Spacer()
            Button("Unblock") {
                run(profile, failure: "Couldn't unblock") { try await friends.unblock(profile.uid) }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColors.accent)
            .disabled(busy.contains(profile.uid))
        }
    }

    // MARK: - Actions

    private func run(_ profile: FriendProfile, failure: String, _ action: @escaping () async throws -> Void) {
        guard !busy.contains(profile.uid) else { return }
        busy.insert(profile.uid)
        Task {
            do {
                try await action()
            } catch {
                showSocialNotice(title: failure, message: error.localizedDescription)
            }
            busy.remove(profile.uid)
        }
    }

    private func report(_ profile: FriendProfile, _ kind: ReportKind) {
        guard !busy.contains(profile.uid) else { return }
        busy.insert(profile.uid)
        Task {
            do {
                try await friends.report(profile.uid, kind: kind)
                thanksTarget = profile
            } catch {
                showSocialNotice(title: "Couldn't send report", message: error.localizedDescription)
            }
            busy.remove(profile.uid)
        }
    }
}
