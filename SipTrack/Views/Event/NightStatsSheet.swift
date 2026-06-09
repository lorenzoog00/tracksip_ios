import SwiftUI

private struct BACIntelligenceData {
    let timeline: [BACDataPoint]
    let peakPoint: BACDataPoint?
    let minutesAboveLimit: Int

    init(timeline: [BACDataPoint], bacLimit: Double) {
        self.timeline = timeline
        self.peakPoint = timeline.max(by: { $0.bac < $1.bac })
        self.minutesAboveLimit = timeline.filter { $0.bac > bacLimit }.count * 5
    }

    static let empty = BACIntelligenceData(timeline: [], bacLimit: 0.08)
}

// MARK: - NightStatsSheet

struct NightStatsSheet: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

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
            return sum + Int(dt.caloriesPerServing * Double(entry.quantity))
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
        // Approximate: cumulative BAC peaks after the last drink.
        // Use the highest marginal drink as a proxy for peak magnitude,
        // and the most recent entry timestamp as the time it likely peaked.
        guard let lastEntry = entries.last else { return (0, 0) }
        var peak: Double = 0
        for entry in entries {
            guard let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { continue }
            let bac = marginalBAC(drinkType: dt, profile: appState.userProfile) * Double(entry.quantity)
            peak += bac
        }
        let minutesAgo = max(0, Int(Date().timeIntervalSince(lastEntry.timestamp) / 60))
        return (peak, minutesAgo)
    }

    // MARK: - BAC Intelligence

    private enum BACPhase { case absorbing, atPeak, eliminating }

    private var bacData: BACIntelligenceData {
        guard let start = event?.startTime, !entries.isEmpty else { return .empty }
        let timeline = BACCalculator.bacTimeline(
            entries: entries,
            drinkTypes: appState.allDrinkTypes,
            profile: appState.userProfile,
            eventStart: start,
            stomachState: event?.stomachState ?? .empty,
            stomachStateTimestamp: event?.stomachStateTimestamp,
            foodEntries: appState.foodEntries.filter { $0.eventId == eventId }
        )
        return BACIntelligenceData(timeline: timeline, bacLimit: bacLimit)
    }

    private var bacTimelinePoints: [BACDataPoint] { bacData.timeline }
    private var peakPoint: BACDataPoint? { bacData.peakPoint }
    private var peakBAC: Double { peakPoint?.bac ?? 0 }
    private var peakTime: Date? { peakPoint?.date }

    private var bacPhase: BACPhase {
        guard peakBAC > 0.001 else { return .absorbing }
        let delta = peakBAC - currentBAC
        // At peak: BAC within 0.5% of highest point
        if delta <= 0.005 { return .atPeak }
        // Plateau: peaked less than 20 min ago and still barely dropping
        if let pt = peakTime, Date().timeIntervalSince(pt) < 1200 && delta < 0.01 { return .atPeak }
        // Eliminating: clearly below peak
        if currentBAC < peakBAC - 0.005 { return .eliminating }
        return .absorbing
    }

    private var minutesAboveLimit: Int { bacData.minutesAboveLimit }

    private var hoursToZeroBAC: Double {
        BACCalculator.hoursToZeroBAC(currentBAC, profile: appState.userProfile)
    }

    private var peakFraction: Double {
        guard let pt = peakTime, let start = event?.startTime else { return 0 }
        let totalElapsed = max(1, Date().timeIntervalSince(start))
        return max(0, min(1.0, pt.timeIntervalSince(start) / totalElapsed))
    }

    // MARK: - BAC Intelligence Helpers

    private var phaseColor: Color {
        switch bacPhase {
        case .absorbing:   return Color(hex: "#FF6B6B")
        case .atPeak:      return Color(hex: "#F0A830")
        case .eliminating: return Color(hex: "#4CD964")
        }
    }

    private var phaseLabel: String {
        switch bacPhase {
        case .absorbing:   return "▲ Still absorbing"
        case .atPeak:      return "▲ At your peak"
        case .eliminating: return "▼ Eliminating — BAC dropping"
        }
    }

    private var soberInTile: some View {
        let h = Int(hoursToZeroBAC)
        let m = Int((hoursToZeroBAC - Double(h)) * 60)
        let soberTime = Calendar.current.date(byAdding: .minute, value: Int(hoursToZeroBAC * 60), to: Date())
        return VStack(alignment: .leading, spacing: 4) {
            Text("SOBER IN")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#5BC8FF"))
            Text(currentBAC < 0.005 ? "Now" : "\(h)h \(String(format: "%02d", m))m")
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: "#5BC8FF"))
            if let st = soberTime, currentBAC >= 0.005 {
                Text("~ \(st, format: .dateTime.hour().minute())")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#5BC8FF").opacity(0.2), lineWidth: 1))
    }

    private var bacArcBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BAC ACROSS THE NIGHT")
                .font(.system(size: 7, weight: .black))
                .tracking(1.5)
                .foregroundStyle(AppColors.textTertiary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(AppColors.border.opacity(0.4))
                        .frame(height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if !bacTimelinePoints.isEmpty {
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [Color(hex: "#4CD964"), Color(hex: "#F0A830"), Color(hex: "#FF6B6B"), Color(hex: "#F0A830")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(height: 8)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if peakBAC > 0.001 && !bacTimelinePoints.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 2, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 1))
                            .offset(x: max(0, geo.size.width * peakFraction - 1))
                            .offset(y: -3)
                    }
                }
            }
            .frame(height: 8)
            .padding(.top, 4)

            HStack {
                Text("start")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                if peakBAC > 0.001 {
                    Text("↑ peak")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FF6B6B"))
                }
                Spacer()
                Text("now")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
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
                        bacIntelligenceSection
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
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Section: BAC Intelligence

    private var bacIntelligenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Phase badge
            HStack {
                Text(phaseLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(phaseColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(phaseColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(phaseColor.opacity(0.25), lineWidth: 1))

            // Peak + Current BAC tiles
            HStack(spacing: 10) {
                peakBACTile
                currentBACTile
            }

            // Arc bar
            bacArcBar

            // Driving-mode only
            if event?.drivingMode == true {
                HStack(spacing: 10) {
                    soberInTile
                    aboveLimitTile
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var peakBACTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PEAK BAC")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#FF6B6B"))
            if peakBAC > 0.001 {
                Text(String(format: "%.3f", peakBAC))
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(hex: "#FF6B6B"))
                if let pt = peakTime {
                    Text("at \(pt, format: .dateTime.hour().minute())")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
            } else {
                Text("—")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                Text("still rising")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#FF6B6B").opacity(0.2), lineWidth: 1))
    }

    private var currentBACTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT BAC")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#F0A830"))
            Text(String(format: "%.3f", currentBAC))
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: "#F0A830"))
            Text(bacPhase == .eliminating && peakBAC > 0
                 ? String(format: "↓ %.3f from peak", peakBAC - currentBAC)
                 : "↑ rising")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F0A830").opacity(0.2), lineWidth: 1))
    }

    private var aboveLimitTile: some View {
        let exceeded = minutesAboveLimit > 0
        return VStack(alignment: .leading, spacing: 4) {
            Text("ABOVE LIMIT")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(exceeded ? Color(hex: "#FF6B6B") : AppColors.textTertiary)
            Text("\(minutesAboveLimit) min")
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(exceeded ? Color(hex: "#FF6B6B") : Color(hex: "#4CD964"))
            Text("tonight so far")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            exceeded ? Color(hex: "#FF6B6B").opacity(0.2) : AppColors.border,
            lineWidth: 1))
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

            ForEach(facts, id: \.text) { fact in
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
        DrinkTimelineCard(entry: entry, appState: appState, bacLimit: bacLimit)
    }

    private func progressColor(for progress: Double) -> Color {
        if progress < 0.5 {
            return AppColors.success
        } else if progress < 0.8 {
            return Color(hex: "#FFB347")
        } else {
            return AppColors.danger
        }
    }
}

// MARK: - Drink Timeline Card (extracted to avoid type-check timeout)

private struct DrinkTimelineCard: View {
    let entry: DrinkEntry
    let appState: AppState
    let bacLimit: Double

    private var dt: DrinkType? {
        appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId })
    }

    private var marginalBAC: Double {
        guard let dt else { return 0 }
        let alcoholGrams = (dt.defaultVolumeMl / 1000.0) * (dt.defaultAbv / 100.0) * 789.0
        let r: Double = appState.userProfile.sex == .female ? 0.55 : 0.68
        return (alcoholGrams / (appState.userProfile.weightKg * r * 10.0)) * Double(entry.quantity)
    }

    private var barProgress: Double { min(1.0, marginalBAC / max(0.001, bacLimit)) }

    private var barColor: Color {
        if barProgress < 0.5 { return AppColors.success }
        if barProgress < 0.8 { return Color(hex: "#FFB347") }
        return AppColors.danger
    }

    private var calories: Int {
        Int((dt?.caloriesPerServing ?? 0) * Double(entry.quantity))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(AppColors.border.opacity(0.4))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(barColor)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: barProgress, anchor: .leading)
                }
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))

            HStack {
                Text(dt?.name ?? "Unknown Drink")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Spacer()
                Text(String(format: "+%.3f BAC", marginalBAC))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barColor)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            HStack {
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                if calories > 0 {
                    Text("\(calories) cal")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border.opacity(0.5), lineWidth: 1))
    }
}

