import SwiftUI

// MARK: - NightStatsSheet

struct NightStatsSheet: View {
    let eventId: String
    var opensAtTimeline = false
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var entries: [DrinkEntry] {
        appState.entries.filter { $0.eventId == eventId }.sorted { $0.timestamp < $1.timestamp }
    }
    private var waterEntries: [WaterEntry] {
        appState.waterEntries.filter { $0.eventId == eventId }.sorted { $0.timestamp < $1.timestamp }
    }
    private var bacLimit: Double { event?.bacLimit ?? appState.userProfile.resolvedBACLimit }
    private var hoursElapsed: Double {
        guard let start = event?.startTime else { return 0.01 }
        return max(0.01, Date().timeIntervalSince(start) / 3600)
    }
    private var drinkCount: Int { entries.reduce(0) { $0 + $1.quantity } }
    private var waterCount: Int { waterEntries.count }
    private var totalCalories: Int {
        Int(entries.reduce(0.0) { sum, entry in
            guard let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { return sum }
            let vol = entry.volumeOverrideMl ?? dt.defaultVolumeMl
            return sum + dt.calories(volumeMl: vol, quantity: entry.quantity)
        })
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

    // Per-drink BAC added, from the same integrated model as the night curve.
    private var drinkContributions: [String: Double] {
        guard let start = event?.startTime else { return [:] }
        return BACCalculator.drinkContributions(
            entries: entries,
            drinkTypes: appState.allDrinkTypes,
            profile: appState.userProfile,
            eventStart: start,
            stomachState: event?.stomachState ?? .empty,
            stomachStateTimestamp: event?.stomachStateTimestamp,
            foodEntries: appState.foodEntries.filter { $0.eventId == eventId }
        )
    }

    // MARK: - BAC Intelligence

    private enum BACPhase { case absorbing, atPeak, eliminating, zero }

    private func makeChartData() -> NightBACChartData? {
        guard let event else { return nil }
        _ = appState.bacTick
        let now = Date.now
        let logged = entries.filter { $0.timestamp <= now }
        let profile = appState.userProfile
        let drinkTypes = appState.allDrinkTypes
        let foods = appState.foodEntries.filter { $0.eventId == eventId && $0.timestamp <= now }
        let stomach = event.stomachState ?? .empty
        let timeline = BACCalculator.bacTimeline(
            entries: logged, drinkTypes: drinkTypes, profile: profile, eventStart: event.startTime,
            stomachState: stomach, stomachStateTimestamp: event.stomachStateTimestamp, foodEntries: foods
        )
        let current = BACCalculator.currentBAC(
            entries: logged, waterEntries: waterEntries, drinkTypes: drinkTypes, profile: profile,
            eventStart: event.startTime, stomachState: stomach, stomachStateTimestamp: event.stomachStateTimestamp,
            foodEntries: foods, asOf: now
        )
        return NightBACChartData(
            eventStart: event.startTime, now: now, currentBAC: current, samples: timeline,
            entries: logged, drinkTypes: drinkTypes
        )
    }

    private func bacPhase(data: NightBACChartData, peak: BACDataPoint?) -> BACPhase {
        let current = data.current.bac
        if data.projection.contains(where: { $0.bac > current + 0.005 }) { return .absorbing }
        guard let peak, current > 0 else { return .zero }
        let delta = peak.bac - current
        if delta <= 0.005 || (data.current.date.timeIntervalSince(peak.date) < 1200 && delta < 0.01) {
            return .atPeak
        }
        return .eliminating
    }

    private func phaseColor(_ phase: BACPhase) -> Color {
        switch phase {
        case .absorbing:   return Color(hex: "#FF6B6B")
        case .atPeak:      return Color(hex: "#F0A830")
        case .eliminating: return Color(hex: "#4CD964")
        case .zero:        return AppColors.textSecondary
        }
    }

    private func phaseLabel(_ phase: BACPhase) -> String {
        switch phase {
        case .absorbing:   return "▲ Still absorbing"
        case .atPeak:      return "▲ At your peak"
        case .eliminating: return "▼ Eliminating — BAC dropping"
        case .zero:        return "Estimated BAC at zero"
        }
    }

    private func soberInTile(currentBAC: Double) -> some View {
        let hoursToZeroBAC = BACCalculator.hoursToZeroBAC(currentBAC, profile: appState.userProfile)
        let h = Int(hoursToZeroBAC)
        let m = Int((hoursToZeroBAC - Double(h)) * 60)
        let soberTime = Calendar.current.date(byAdding: .minute, value: Int(hoursToZeroBAC * 60), to: Date())
        return VStack(alignment: .leading, spacing: 4) {
            Text("SOBER IN")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#5BC8FF"))
            Text(currentBAC < 0.005 ? "Now" : "\(h)h \(String(format: "%02d", m))m")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: "#5BC8FF"))
            if let st = soberTime, currentBAC >= 0.005 {
                Text("~ \(st, format: .dateTime.hour().minute())")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#5BC8FF").opacity(0.2), lineWidth: 1))
    }

    // MARK: - Body

    var body: some View {
        let timelineAnchor = "timeline"
        let chartData = makeChartData()
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(spacing: 16) {
                            paceSection
                            if let chartData {
                                bacIntelligenceSection(chartData)
                                NightBACChartCard(data: chartData)
                                    .padding(.horizontal, 16)
                            }
                            totalsSection
                            timelineSection.id(timelineAnchor)
                            Color.clear.frame(height: 20)
                        }
                        .padding(.top, 16)
                    }
                    .task {
                        guard opensAtTimeline else { return }
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        scroll.scrollTo(timelineAnchor, anchor: .top)
                    }
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

    private func bacIntelligenceSection(_ data: NightBACChartData) -> some View {
        let peak = data.history.max { $0.bac < $1.bac }
        let phase = bacPhase(data: data, peak: peak)
        let color = phaseColor(phase)
        let minutesAboveLimit = data.history.dropLast().filter { $0.bac > bacLimit }.count * 5
        return VStack(alignment: .leading, spacing: 10) {
            // Phase badge
            HStack {
                Text(phaseLabel(phase))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1))

            // Peak + Current BAC tiles
            HStack(spacing: 10) {
                peakBACTile(peak)
                currentBACTile(bac: data.current.bac, peakBAC: peak?.bac ?? 0, phase: phase)
            }

            // Driving-mode only
            if event?.drivingMode == true {
                HStack(spacing: 10) {
                    soberInTile(currentBAC: data.current.bac)
                    aboveLimitTile(minutes: minutesAboveLimit)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func peakBACTile(_ peak: BACDataPoint?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PEAK BAC")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#FF6B6B"))
            if let peak, peak.bac > 0.001 {
                Text(String(format: "%.3f", peak.bac))
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(hex: "#FF6B6B"))
                Text("at \(peak.date, format: .dateTime.hour().minute())")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                Text("—")
                    .font(.system(size: 28, weight: .black, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                Text("No peak yet")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#FF6B6B").opacity(0.2), lineWidth: 1))
    }

    private func currentBACTile(bac: Double, peakBAC: Double, phase: BACPhase) -> some View {
        let detail = switch phase {
        case .absorbing: "↑ rising"
        case .atPeak: "Near peak"
        case .eliminating: String(format: "↓ %.3f from peak", peakBAC - bac)
        case .zero: "Estimate"
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT BAC")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#F0A830"))
            Text(String(format: "%.3f", bac))
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: "#F0A830"))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F0A830").opacity(0.2), lineWidth: 1))
    }

    private func aboveLimitTile(minutes: Int) -> some View {
        let exceeded = minutes > 0
        return VStack(alignment: .leading, spacing: 4) {
            Text("ABOVE LIMIT")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(exceeded ? Color(hex: "#FF6B6B") : AppColors.textTertiary)
            Text("\(minutes) min")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(exceeded ? Color(hex: "#FF6B6B") : Color(hex: "#4CD964"))
            Text("tonight so far")
                .font(.system(size: 13))
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
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
            Text(String(format: "%.1f", drinksPerHour))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            Text("drinks / hr")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .premiumCard(radius: 14)
    }

    private var timeTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIME OUT")
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
            Text(formattedDuration)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            if let start = event?.startTime {
                Text("since \(start, format: .dateTime.hour().minute())")
                    .font(.system(size: 14, weight: .medium))
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .premiumCard(radius: 12)
    }

    // MARK: - Section 4: Timeline

    private var timelineSection: some View {
        let contributions = drinkContributions
        return VStack(alignment: .leading, spacing: 0) {
            Text("TIMELINE")
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            if timelineItems.isEmpty {
                Text("No drinks logged yet — your night starts here.")
                    .font(.system(size: 16))
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
                            timelineCard(for: item, contributions: contributions)
                                .padding(.bottom, 4)

                            // Gap label
                            if index < timelineItems.count - 1 {
                                let nextItem = timelineItems[index + 1]
                                let gap = Int(nextItem.timestamp.timeIntervalSince(item.timestamp) / 60)
                                if gap > 0 {
                                    HStack {
                                        Text("\(gap) min ↓")
                                            .font(.system(size: 13, weight: .medium, design: .monospaced))
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
    private func timelineCard(for item: TimelineItem, contributions: [String: Double]) -> some View {
        switch item {
        case .water(let water):
            waterCard(water)
        case .drink(let entry):
            DrinkTimelineCard(
                entry: entry, appState: appState, bacLimit: bacLimit,
                marginalBAC: contributions[entry.id] ?? 0
            )
        }
    }

    private func waterCard(_ water: WaterEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "drop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.water)
                Text("Hydration ✓")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.water)
                Spacer()
                Text(water.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            }
            Text(String(format: "%.0f ml", water.volumeMl))
                .font(.system(size: 14))
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
    let marginalBAC: Double

    private var dt: DrinkType? {
        appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId })
    }

    private var barProgress: Double { min(1.0, marginalBAC / max(0.001, bacLimit)) }

    private var barColor: Color {
        if barProgress < 0.5 { return AppColors.success }
        if barProgress < 0.8 { return Color(hex: "#FFB347") }
        return AppColors.danger
    }

    private var calories: Int {
        guard let dt else { return 0 }
        return Int(dt.calories(volumeMl: entry.volumeOverrideMl ?? dt.defaultVolumeMl, quantity: entry.quantity))
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Spacer()
                Text(String(format: "+%.3f BAC", marginalBAC))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barColor)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            HStack {
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                if calories > 0 {
                    Text("\(calories) cal")
                        .font(.system(size: 14))
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

