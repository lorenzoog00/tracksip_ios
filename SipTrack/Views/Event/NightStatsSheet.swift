import SwiftUI

// MARK: - NightStatsSheet

struct NightStatsSheet: View {
    let eventId: String
    @EnvironmentObject var appState: AppState

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var entries: [DrinkEntry] {
        appState.entries.filter { $0.eventId == eventId }.sorted { $0.timestamp < $1.timestamp }
    }
    private var waterEntries: [WaterEntry] {
        appState.waterEntries.filter { $0.eventId == eventId }.sorted { $0.timestamp < $1.timestamp }
    }
    private var currentBAC: Double { appState.currentBAC(for: eventId) }
    private var bacLimit: Double { event?.bacLimit ?? appState.userProfile.resolvedBACLimit }
    private var hoursElapsed: Double {
        guard let start = event?.startTime else { return 0.01 }
        return max(0.01, Date().timeIntervalSince(start) / 3600)
    }
    private var drinkCount: Int { entries.count }
    private var waterCount: Int { waterEntries.count }
    private var totalCalories: Int {
        entries.reduce(0) { sum, entry in
            guard let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { return sum }
            return sum + (Int(dt.caloriesPerServing) * entry.quantity)
        }
    }
    private var drinksPerHour: Double { Double(drinkCount) / hoursElapsed }

    // Timeline merged entries (chronological)
    private enum TimelineItem: Identifiable {
        case drink(DrinkEntry)
        case water(WaterEntry)

        var id: String {
            switch self {
            case .drink(let e): return "d-\(e.id)"
            case .water(let w): return "w-\(w.id)"
            }
        }
        var timestamp: Date {
            switch self {
            case .drink(let e): return e.timestamp
            case .water(let w): return w.timestamp
            }
        }
    }

    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = entries.map { .drink($0) } + waterEntries.map { .water($0) }
        items.sort { $0.timestamp < $1.timestamp }
        return items
    }

    // Marginal BAC helper
    private func marginalBAC(drinkType: DrinkType, profile: UserProfile) -> Double {
        let volumeMl = drinkType.defaultVolumeMl
        let abv = drinkType.defaultAbv
        let alcoholGrams = (volumeMl / 1000.0) * (abv / 100.0) * 789.0
        let r: Double = profile.sex == .female ? 0.55 : 0.68
        return alcoholGrams / (profile.weightKg * r * 10.0)
    }

    private var peakBACInfo: (peakBAC: Double, minutesAgo: Int) {
        var peak: Double = 0
        var peakTime: Date = Date()
        for entry in entries {
            guard let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { continue }
            let bac = marginalBAC(drinkType: dt, profile: appState.userProfile) * Double(entry.quantity)
            if bac > peak {
                peak = bac
                peakTime = entry.timestamp
            }
        }
        let minutesAgo = Int(Date().timeIntervalSince(peakTime) / 60)
        return (peak, minutesAgo)
    }

    private var drinksThisHour: Int {
        let cutoff = Date().addingTimeInterval(-3600)
        return entries.filter { $0.timestamp >= cutoff }.count
    }

    private var facts: [NightFact] {
        let (peakBAC, peakMinsAgo) = peakBACInfo
        return computeNightFacts(
            drinkCount: drinkCount,
            waterCount: waterCount,
            currentBAC: currentBAC,
            bacLimit: bacLimit,
            hoursElapsed: hoursElapsed,
            totalCalories: totalCalories,
            peakBAC: peakBAC,
            peakBACMinutesAgo: peakMinsAgo,
            drinksThisHour: drinksThisHour,
            avgDrinksPerHour: drinksPerHour
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        paceSection
                        totalsSection
                        if !facts.isEmpty { factsSection }
                        timelineSection
                        Color.clear.frame(height: 20)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("How am I going?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { }
                }
            }
        }
    }

    // MARK: - Section 1: Pace + Duration

    private var paceSection: some View {
        HStack(spacing: 12) {
            paceTile
            timeTile
        }
        .padding(.horizontal, 16)
    }

    private var paceTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PACE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
            Text(String(format: "%.1f", drinksPerHour))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            Text("drinks / hr")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(radius: 14)
    }

    private var timeTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIME OUT")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
            Text(formattedDuration)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            if let start = event?.startTime {
                Text("since \(start, format: .dateTime.hour().minute())")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(radius: 14)
    }

    private var formattedDuration: String {
        let totalMinutes = Int(hoursElapsed * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return String(format: "%dh%02dm", h, m)
    }

    // MARK: - Section 2: Quick Totals

    private var totalsSection: some View {
        HStack(spacing: 10) {
            totalTile(
                value: "\(drinkCount)",
                label: "Drinks",
                icon: "mug.fill",
                color: AppColors.accent
            )
            totalTile(
                value: "\(waterCount)",
                label: "Water",
                icon: "drop.fill",
                color: AppColors.water
            )
            totalTile(
                value: "\(totalCalories)",
                label: "Calories",
                icon: "flame.fill",
                color: Color(hex: "#FF6B6B")
            )
        }
        .padding(.horizontal, 16)
    }

    private func totalTile(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .premiumCard(radius: 12)
    }

    // MARK: - Section 3: Facts

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INSIGHTS")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)

            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                factRow(fact)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func factRow(_ fact: NightFact) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: fact.isSafetyAlert ? "exclamationmark.triangle.fill" : "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(fact.isSafetyAlert ? AppColors.danger : AppColors.accent)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
            Text(fact.text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fact.isSafetyAlert ? AppColors.danger.opacity(0.08) : AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    fact.isSafetyAlert ? AppColors.danger.opacity(0.2) : AppColors.border.opacity(0.5),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Section 4: Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TIMELINE")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if timelineItems.isEmpty {
                Text("No drinks logged yet — your night starts here.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 16)
            } else {
                ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        // Dot + line column
                        VStack(spacing: 0) {
                            dotView(for: item)
                            if index < timelineItems.count - 1 {
                                Rectangle()
                                    .fill(AppColors.border.opacity(0.5))
                                    .frame(width: 2)
                                    .frame(minHeight: 40)
                            }
                        }
                        .frame(width: 20)

                        // Card
                        VStack(spacing: 0) {
                            timelineCard(for: item)
                                .padding(.bottom, 4)

                            // Gap label
                            if index < timelineItems.count - 1 {
                                let nextItem = timelineItems[index + 1]
                                let gap = Int(nextItem.timestamp.timeIntervalSince(item.timestamp) / 60)
                                if gap > 0 {
                                    HStack {
                                        Text("\(gap) min ↓")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundStyle(AppColors.textTertiary)
                                        Spacer()
                                    }
                                    .padding(.leading, 4)
                                    .padding(.bottom, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func dotView(for item: TimelineItem) -> some View {
        Circle()
            .fill(dotColor(for: item))
            .frame(width: 10, height: 10)
            .padding(.top, 14)
    }

    private func dotColor(for item: TimelineItem) -> Color {
        switch item {
        case .water:
            return AppColors.water
        case .drink(let entry):
            guard let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else {
                return AppColors.accent
            }
            return dt.color
        }
    }

    @ViewBuilder
    private func timelineCard(for item: TimelineItem) -> some View {
        switch item {
        case .water(let water):
            waterCard(water)
        case .drink(let entry):
            drinkCard(entry)
        }
    }

    private func waterCard(_ water: WaterEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.water)
                Text("Hydration ✓")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.water)
                Spacer()
                Text(water.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text(String(format: "%.0f ml", water.volumeMl))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(12)
        .background(AppColors.water.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.water.opacity(0.2), lineWidth: 1)
        )
    }

    private func drinkCard(_ entry: DrinkEntry) -> some View {
        let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId })
        let bac = dt.map { marginalBAC(drinkType: $0, profile: appState.userProfile) * Double(entry.quantity) } ?? 0
        let progress = min(1.0, bac / max(0.001, bacLimit))
        let progressColor = progressColor(for: progress)
        let cals = Int((dt?.caloriesPerServing ?? 0) * Double(entry.quantity))

        return VStack(alignment: .leading, spacing: 0) {
            // BAC progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppColors.border.opacity(0.4))
                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 2)
            .clipShape(RoundedRectangle(cornerRadius: 1))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let dt = dt {
                        Text(dt.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                    } else {
                        Text("Unknown Drink")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                    }
                    Spacer()
                    Text(String(format: "+%.3f BAC", bac))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(progressColor)
                }
                HStack {
                    Text(entry.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    if cals > 0 {
                        Text("\(cals) cal")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func progressColor(for progress: Double) -> Color {
        if progress < 0.5 {
            return AppColors.success
        } else if progress < 0.8 {
            return Color(hex: "#FFB347")  // amber
        } else {
            return AppColors.danger
        }
    }
}

// MARK: - Preview

#Preview {
    NightStatsSheet(eventId: "preview")
        .environmentObject(AppState())
}
