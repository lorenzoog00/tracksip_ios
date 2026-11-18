import SwiftUI
import UIKit

/// Shows a notice for a social-screen failure that has no inline spot.
func showSocialNotice(title: String, message: String) {
    NoticeCenter.shared.show(Notice(
        icon: "exclamationmark.triangle.fill",
        tone: .danger,
        title: title,
        message: message,
        actions: [NoticeAction("OK") {}]
    ))
}

/// The Home | Social switch at the top of both root screens, in the navigation
/// bar's centre so it sits in the same spot on each. White pill on the selected
/// side; Social carries the friend-request count, or a green dot while a friend
/// is out.
struct AppTabSwitcher: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var friends: FriendsStore
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            segment(.home, title: "Home", icon: "house.fill")
            segment(.social, title: "Social", icon: "person.2.fill")
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: appState.selectedTab)
    }

    private func segment(_ tab: AppTab, title: String, icon: String) -> some View {
        let selected = appState.selectedTab == tab
        return Button {
            guard !selected else { return }
            Haptics.shared.play(.selection)
            appState.selectedTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                if tab == .social { socialIndicator(selected: selected) }
            }
            .foregroundStyle(selected ? Color.black : AppColors.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle(tab, title: title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func socialIndicator(selected: Bool) -> some View {
        if friends.pendingCount > 0 {
            Text("\(friends.pendingCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(minWidth: 18, minHeight: 18)
                .background(AppColors.danger, in: Capsule())
        } else if friends.liveCount > 0 {
            Circle()
                .fill(AppColors.success)
                .frame(width: 7, height: 7)
        }
    }

    private func accessibilityTitle(_ tab: AppTab, title: String) -> String {
        guard tab == .social else { return title }
        if friends.pendingCount > 0 { return "Social, \(friends.pendingCount) friend requests" }
        if friends.liveCount > 0 { return "Social, friends out now" }
        return title
    }
}
