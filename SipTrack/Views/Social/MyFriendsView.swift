import SwiftUI

/// Requests, friends and blocked people, with the actions to manage them.
struct MyFriendsView: View {
    @EnvironmentObject var friends: FriendsStore
    @StateObject private var coordinator = FriendActionCoordinator()
    @State private var blockedExpanded = false
    /// The friend whose profile a row tap pushed.
    @State private var openedProfile: FriendProfile?

    private func isLive(_ profile: FriendProfile) -> Bool {
        let now = Date()
        return friends.feed.contains { $0.profile.uid == profile.uid && $0.night.isLive(now: now) }
    }

    /// Requests still to answer. One being declined goes at once (it comes back
    /// if the decline fails); one accepted shows "Friends" until it is listed
    /// under Friends.
    private var requests: [FriendProfile] {
        friends.incoming.filter { request in
            friends.rowState(for: request.uid) != .add
                && !friends.friends.contains { $0.uid == request.uid }
        }
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

                if !requests.isEmpty {
                    Section("Requests") {
                        ForEach(requests, id: \.uid) { profile in
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
        .navigationDestination(isPresented: openedProfileBinding) {
            if let openedProfile {
                FriendProfileView(profile: openedProfile)
            }
        }
    }

    private var openedProfileBinding: Binding<Bool> {
        Binding(
            get: { openedProfile != nil },
            set: { if !$0 { openedProfile = nil } }
        )
    }

    // MARK: - Rows

    private func requestRow(_ profile: FriendProfile) -> some View {
        // Accepted, the row says so at once; the call runs behind it.
        let accepted = friends.rowState(for: profile.uid) == .friend
        let disabled = coordinator.isBusy(profile) || friends.pending.isPending(profile.uid)
        return HStack(spacing: 12) {
            AvatarView(profile: profile, size: 40)
            ProfileNameLabel(profile: profile)
            Spacer()
            if accepted {
                Text("Friends")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(AppColors.textSecondary)
                    .background(AppColors.border)
                    .clipShape(Capsule())
            } else {
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
            }
            ReportBlockMenu(profile: profile, coordinator: coordinator)
        }
    }

    /// The row opens their profile (and their night from there); the ⋯ menu and the
    /// swipe keep Remove, Block and Report.
    private func friendRow(_ profile: FriendProfile) -> some View {
        HStack(spacing: 12) {
            Button {
                openedProfile = profile
            } label: {
                HStack(spacing: 12) {
                    AvatarView(profile: profile, size: 40)
                    ProfileNameLabel(profile: profile)
                    if isLive(profile) {
                        Circle()
                            .fill(AppColors.success)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Live now")
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            // Borderless: only this part of the row opens the profile, so the ⋯ menu
            // keeps its own tap.
            .buttonStyle(.borderless)
            .accessibilityHint("Opens their profile")
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
            // A lone "@username" stays the plain 17 pt it was before names.
            ProfileNameLabel(profile: profile, size: 17, usernameWeight: .regular)
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
