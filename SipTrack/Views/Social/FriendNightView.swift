import SwiftUI
import Charts

/// One friend's shared night: BAC curve, drink timeline and stats.
/// Shows only what `SharedNight` carries.
struct FriendNightView: View {
    @EnvironmentObject var friends: FriendsStore
    let item: FeedItem

    /// Prefer the freshest copy from the store; fall back to the one we were opened with.
    private var current: FeedItem {
        friends.feed.first { $0.id == item.id } ?? item
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let item = current
            let night = item.night
            let live = night.isLive(now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(item, now: now, live: live)
                    chart(night, now: now, live: live)
                    stats(night, now: now, live: live)
                    drinkTimeline(night)
                }
                .padding(16)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("@\(item.profile.username)")
        .navigationBarTitleDisplayMode(.inline)
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

    private struct Point: Identifiable {
        let date: Date
        let bac: Double
        var id: Date { date }
    }

    private func chart(_ night: SharedNight, now: Date, live: Bool) -> some View {
        let points = night.samples.enumerated().map { index, value in
            Point(
                date: night.startedAt.addingTimeInterval(Double(index) * SharedNight.sampleInterval),
                bac: value
            )
        }
        let yMax = max(night.peakBAC * 1.2, 0.08)
        let end = max(points.last?.date ?? night.startedAt, night.startedAt.addingTimeInterval(SharedNight.sampleInterval))
        return Chart {
            ForEach(points) { point in
                AreaMark(x: .value("Time", point.date), y: .value("BAC", point.bac))
                    .foregroundStyle(AppColors.accent.opacity(0.12))
                LineMark(x: .value("Time", point.date), y: .value("BAC", point.bac))
                    .foregroundStyle(AppColors.accentWarm)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(night.drinks.enumerated()), id: \.offset) { _, drink in
                PointMark(x: .value("Drink", drink.at), y: .value("BAC", night.bac(at: drink.at)))
                    .foregroundStyle(AppColors.accent)
                    .symbolSize(18)
            }
            if live, (night.startedAt...end).contains(now) {
                RuleMark(x: .value("Now", now))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.45))
            }
        }
        .chartXScale(domain: night.startedAt...end)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(AppColors.border)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(AppColors.border)
                AxisValueLabel().foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(height: 200)
        .padding(12)
        .background(AppColors.card, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blood alcohol curve, peak \(FriendNightFormat.bac(night.peakBAC))")
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
