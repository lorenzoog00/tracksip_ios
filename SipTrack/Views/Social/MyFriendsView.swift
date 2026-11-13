import SwiftUI

/// Requests, friends and blocked people, with the actions to manage them.
struct MyFriendsView: View {
    @EnvironmentObject var friends: FriendsStore
    @StateObject private var coordinator = FriendActionCoordinator()
    @State private var blockedExpanded = false

    private func isLive(_ profile: FriendProfile) -> Bool {
        let now = Date()
        return friends.feed.contains { $0.id == profile.uid && $0.night.isLive(now: now) }
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
                                Button("Remove", role: .destructive) { coordinator.removeTarget = profile }
                                    .disabled(coordinator.isBusy(profile))
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
        .friendActionDialogs(coordinator)
    }

    // MARK: - Rows

    private func requestRow(_ profile: FriendProfile) -> some View {
        let disabled = coordinator.isBusy(profile)
        return HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            Text("@\(profile.username)")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.text)
            Spacer()
            Button {
                coordinator.run(profile, failure: "Couldn't accept request") { try await friends.respond(to: profile.uid, accept: true) }
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
                coordinator.run(profile, failure: "Couldn't decline request") { try await friends.respond(to: profile.uid, accept: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(8)
            }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .accessibilityLabel("Decline")
            ReportBlockMenu(profile: profile, coordinator: coordinator)
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
                Button("Remove") { coordinator.removeTarget = profile }
                Button("Block", role: .destructive) { coordinator.blockTarget = profile }
                Button("Report") { coordinator.reportTarget = profile }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .disabled(coordinator.isBusy(profile))
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
                coordinator.run(profile, failure: "Couldn't unblock") { try await friends.unblock(profile.uid) }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColors.accent)
            .disabled(coordinator.isBusy(profile))
        }
    }
}
