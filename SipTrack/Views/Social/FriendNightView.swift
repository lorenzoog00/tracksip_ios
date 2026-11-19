import SwiftUI
import Charts

/// One friend's shared night: BAC curve, drink timeline and stats.
/// Shows only what `SharedNight` carries.
struct FriendNightView: View {
    @EnvironmentObject var friends: FriendsStore
    let item: FeedItem

    /// The store's copy only: a removed friend, deleted night or incognito switch drops it.
    private var current: FeedItem? {
        if let mine = friends.myNight, mine.id == item.id { return mine }
        return friends.feed.first { $0.id == item.id }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            if let item = current, item.night.expiresAt > now {
                content(item, now: now)
            } else {
                Text("This night is no longer available.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("@\(item.profile.username)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ item: FeedItem, now: Date) -> some View {
        let night = item.night
        let live = night.isLive(now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(item, now: now, live: live)
                chart(night, now: now, live: live)
                stats(night, now: now, live: live)
                if !night.drinks.isEmpty { drinkTimeline(night) }
            }
            .padding(16)
        }
    }

    // MARK: - Header

    private func header(_ item: FeedItem, now: Date, live: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(profile: item.profile, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("@\(item.profile.username)")
                    .font(.headline)
                    .foregroundStyle(AppColors.text)
                if live {
                    HStack(spacing: 6) {
                        LiveDot()
                        Text("Live")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.success)
                    }
                } else {
                    let ended = item.night.endedAt ?? item.night.lastDrinkAt
                    Text("ended \(FriendNightFormat.ago(now.timeIntervalSince(ended)))")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            if live {
                let value = item.night.bac(at: now)
                Text(FriendNightFormat.bac(value))
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(IntoxicationStage.stage(for: value).color)
            }
        }
    }

    // MARK: - Chart

    /// The same BAC card as your own Stats. Before the first drink there is no
    /// curve to draw, so a quiet empty card instead of axes with nothing on them.
    @ViewBuilder
    private func chart(_ night: SharedNight, now: Date, live: Bool) -> some View {
        if night.drinks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityHidden(true)
                Text("No drinks yet")
                    .font(.headline)
                    .foregroundStyle(AppColors.text)
                Text(live ? "Their BAC curve shows up after the first drink." : "This night ended without any drinks.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 16)
            .premiumCard(radius: 14)
        } else {
            NightBACChartCard(data: NightBACChartData(shared: night, now: now))
        }
    }

    // MARK: - Stats

    private func stats(_ night: SharedNight, now: Date, live: Bool) -> some View {
        let endpoint = night.endedAt ?? (live ? now : night.lastDrinkAt)
        return HStack(spacing: 10) {
            stat("Peak", FriendNightFormat.bac(night.peakBAC),
                 color: IntoxicationStage.stage(for: night.peakBAC).color)
            stat("Drinks", "\(night.drinkCount)", color: AppColors.text)
            stat("Duration", FriendNightFormat.duration(endpoint.timeIntervalSince(night.startedAt)),
                 color: AppColors.text)
        }
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Drinks

    private func drinkTimeline(_ night: SharedNight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drinks")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(night.drinks.enumerated()), id: \.offset) { _, drink in
                HStack(spacing: 12) {
                    Image(systemName: FriendNightFormat.symbol(forIcon: drink.icon))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 28)
                    Text(drink.name)
                        .foregroundStyle(AppColors.text)
                    Spacer()
                    Text(drink.at, format: .dateTime.hour().minute())
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.vertical, 6)
            }
        }
    }
}
