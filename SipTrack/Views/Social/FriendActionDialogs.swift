import SwiftUI

/// State and helpers shared by every screen that can remove, block or report someone.
@MainActor
final class FriendActionCoordinator: ObservableObject {
    @Published var removeTarget: FriendProfile?
    @Published var blockTarget: FriendProfile?
    @Published var reportTarget: FriendProfile?
    @Published var thanksTarget: FriendProfile?
    @Published private(set) var busy: Set<String> = []

    func isBusy(_ profile: FriendProfile) -> Bool { busy.contains(profile.uid) }

    func run(_ profile: FriendProfile, failure: String, _ action: @escaping () async throws -> Void) {
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

    func report(_ profile: FriendProfile, _ kind: ReportKind, store: FriendsStore) {
        guard !busy.contains(profile.uid) else { return }
        busy.insert(profile.uid)
        Task {
            do {
                try await store.report(profile.uid, kind: kind)
                thanksTarget = profile
            } catch {
                showSocialNotice(title: "Couldn't send report", message: error.localizedDescription)
            }
            busy.remove(profile.uid)
        }
    }
}

private struct FriendActionDialogs: ViewModifier {
    @EnvironmentObject var friends: FriendsStore
    @ObservedObject var coordinator: FriendActionCoordinator

    private func flag(_ keyPath: ReferenceWritableKeyPath<FriendActionCoordinator, FriendProfile?>) -> Binding<Bool> {
        Binding(
            get: { coordinator[keyPath: keyPath] != nil },
            set: { if !$0 { coordinator[keyPath: keyPath] = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "Remove @\(coordinator.removeTarget?.username ?? "")?",
                isPresented: flag(\.removeTarget),
                presenting: coordinator.removeTarget
            ) { profile in
                Button("Remove", role: .destructive) {
                    coordinator.run(profile, failure: "Couldn't remove friend") { try await friends.remove(profile.uid) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Block @\(coordinator.blockTarget?.username ?? "")?",
                isPresented: flag(\.blockTarget),
                presenting: coordinator.blockTarget
            ) { profile in
                Button("Block", role: .destructive) {
                    coordinator.run(profile, failure: "Couldn't block") { try await friends.block(profile.uid) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { profile in
                Text("@\(profile.username) won't be able to find you or send you requests. They'll also be removed from your friends.")
            }
            .confirmationDialog(
                "Report @\(coordinator.reportTarget?.username ?? "")",
                isPresented: flag(\.reportTarget),
                titleVisibility: .visible,
                presenting: coordinator.reportTarget
            ) { profile in
                Button("Username") { coordinator.report(profile, .username, store: friends) }
                Button("Photo") { coordinator.report(profile, .photo, store: friends) }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "Thanks — we'll review it.",
                isPresented: flag(\.thanksTarget),
                presenting: coordinator.thanksTarget
            ) { profile in
                Button("Block @\(profile.username)", role: .destructive) {
                    coordinator.run(profile, failure: "Couldn't block") { try await friends.block(profile.uid) }
                }
                Button("Done", role: .cancel) {}
            }
    }
}

extension View {
    /// Remove / Block / Report confirmations, driven by the coordinator.
    func friendActionDialogs(_ coordinator: FriendActionCoordinator) -> some View {
        modifier(FriendActionDialogs(coordinator: coordinator))
    }
}

/// "⋯" menu with Report and Block, for people who are not (yet) friends.
struct ReportBlockMenu: View {
    let profile: FriendProfile
    @ObservedObject var coordinator: FriendActionCoordinator

    var body: some View {
        Menu {
            Button("Report") { coordinator.reportTarget = profile }
            Button("Block", role: .destructive) { coordinator.blockTarget = profile }
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
