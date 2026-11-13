import SwiftUI

/// Small formatters shared by the feed and the friend night screen.
enum FriendNightFormat {
    static func bac(_ value: Double) -> String {
        String(format: "%.3f", max(0, value))
    }

    /// "42m" or "3h 12m".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    /// "just now", "12m ago", "3h ago".
    static func ago(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    static func drinkLabel(_ count: Int) -> String {
        count == 1 ? "1 drink" : "\(count) drinks"
    }

    /// Same icon keys as DrinkType; reuse its SF Symbol mapping.
    static func symbol(forIcon icon: String) -> String {
        DrinkType(
            id: "", name: "", defaultVolumeMl: 0, defaultAbv: 0, caloriesPerServing: 0,
            isPreset: false, icon: icon, colorHex: nil
        ).sfSymbol
    }
}

/// Small green dot that pulses while a night is live. Static under Reduce Motion.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AppColors.success)
            .frame(width: 8, height: 8)
            .opacity(reduceMotion ? 1 : (pulsing ? 0.35 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Friends' live nights and the last 24 hours of finished ones.
struct FeedView: View {
    @EnvironmentObject var friends: FriendsStore
    /// Opens the same search destination as the toolbar magnifier.
    let onAddFriend: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let sections = FeedOrdering.sections(friends.feed, now: now)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if friends.friends.isEmpty {
                        emptyFriends
                    } else if sections.live.isEmpty && sections.recent.isEmpty {
                        Text("No nights from your friends in the last 24 hours.")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else {
                        if !sections.live.isEmpty {
                            header("Live now")
                            ForEach(sections.live) { item in
                                NavigationLink {
                                    FriendNightView(item: item)
                                } label: {
                                    FeedRow(item: item, now: now, live: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !sections.recent.isEmpty {
                            header("Last 24 hours")
                            ForEach(sections.recent) { item in
                                NavigationLink {
                                    FriendNightView(item: item)
                                } label: {
                                    FeedRow(item: item, now: now, live: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
            .padding(.top, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private var emptyFriends: some View {
        VStack {
            Button(action: onAddFriend) {
                Text("Add a friend")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(AppColors.accent, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

private struct FeedRow: View {
    let item: FeedItem
    let now: Date
    let live: Bool

    var body: some View {
        let night = item.night
        HStack(spacing: 12) {
            AvatarView(profile: item.profile, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if live { LiveDot() }
                    Text("@\(item.profile.username)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                }
                Text(subtitle(night))
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                let value = live ? night.bac(at: now) : night.peakBAC
                Text(FriendNightFormat.bac(value))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(IntoxicationStage.stage(for: value).color)
                if !live {
                    Text("peak")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(12)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(live ? AppColors.success.opacity(0.4) : AppColors.border, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func subtitle(_ night: SharedNight) -> String {
        let drinks = FriendNightFormat.drinkLabel(night.drinkCount)
        if live {
            return "\(drinks) · \(FriendNightFormat.duration(now.timeIntervalSince(night.startedAt)))"
        }
        let ended = night.endedAt ?? night.lastDrinkAt
        return "\(drinks) · ended \(FriendNightFormat.ago(now.timeIntervalSince(ended)))"
    }
}
