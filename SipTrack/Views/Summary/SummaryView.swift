import SwiftUI
import Charts
import UIKit

struct SummaryView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var notes = ""
    @State private var notesSavedAt: Date? = nil
    @State private var showDeleteConfirm = false
    @State private var showPDFShare = false
    @State private var pdfURL: URL? = nil
    @Environment(\.dismiss) private var dismiss

    private var event: NightEvent?      { appState.events.first { $0.id == eventId } }
    private var eventEntries: [DrinkEntry] { appState.entries.filter { $0.eventId == eventId } }
    private var eventWater: [WaterEntry]   { appState.waterEntries.filter { $0.eventId == eventId } }
    private var eventFood: [FoodEntry]     { appState.foodEntries.filter { $0.eventId == eventId } }

    var body: some View {
        guard let event = event else {
            return AnyView(Text("Event not found").foregroundStyle(AppColors.textSecondary))
        }
        return AnyView(content(event: event))
    }

    private func content(event: NightEvent) -> some View {
        let drinkCount = eventEntries.reduce(0) { $0 + $1.quantity }
        let calories   = appState.totalCalories(for: eventId)
        let r          = BACCalculator.profileR(profile: appState.userProfile)
        let alcoholG   = eventEntries.reduce(0.0) { sum, e in
            let dt  = appState.allDrinkTypes.first { $0.id == e.drinkTypeId }
            let vol = e.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = e.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + BACCalculator.calculateAlcohol(volumeMl: vol, abv: abv, quantity: e.quantity)
        }
        let standardDrinks = BACCalculator.standardDrinks(alcoholGrams: alcoholG)
        let peakBAC  = BACCalculator.estimatePeakBAC(
            entries: eventEntries,
            drinkTypes: appState.allDrinkTypes,
            weightKg: appState.userProfile.weightKg,
            sex: appState.userProfile.sex,
            eventStart: event.startTime,
            r: r
        )
        let hoursToZero = BACCalculator.hoursToZeroBAC(peakBAC)

        let prose = nightProse(event: event, drinkCount: drinkCount, calories: calories, alcoholG: alcoholG, peakBAC: peakBAC)
        let shareText = "[\(event.displayName)] \(eventDateRange(event))\n\n\(prose)\n\nTracked with Tracksip"
        let timeline = BACCalculator.bacTimeline(
            entries: eventEntries,
            drinkTypes: appState.allDrinkTypes,
            profile: appState.userProfile,
            eventStart: event.startTime
        )
        let drivingLimit: Double? = event.drivingMode ? (event.bacLimit ?? appState.userProfile.resolvedBACLimit) : nil
        let meanBACValue = event.endTime.map {
            BACCalculator.meanBACForEvent(entries: eventEntries, drinkTypes: appState.allDrinkTypes, profile: appState.userProfile, eventStart: event.startTime, eventEnd: $0)
        } ?? 0
        let meanBACStage = IntoxicationStage.stage(for: meanBACValue)

        return ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 6) {
                    Text(event.displayName)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text(eventDateRange(event))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(durationString(event.duration))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textTertiary)
                    if let state = event.stomachState, state != .empty {
                        Label("\(state.emoji) \(state.displayName) before drinking", systemImage: "fork.knife")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top)

                // BAC timeline chart
                if !timeline.isEmpty {
                    BACChartView(
                        points: timeline,
                        peakBAC: peakBAC,
                        drivingLimit: drivingLimit,
                        eventEndTime: event.endTime
                    )
                }

                // Drinking pace
                if !eventEntries.isEmpty || !eventWater.isEmpty {
                    DrinkingPaceCard(
                        entries: eventEntries,
                        waterEntries: eventWater,
                        timeline: timeline,
                        eventStart: event.startTime,
                        eventEnd: event.endTime
                    )
                }

                // "Your Night" prose
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your Night", systemImage: "moon.stars.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(prose)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.text)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppColors.surface)
                .cornerRadius(14)
                .padding(.horizontal)

                // Night analysis (AI report + recovery brief)
                NightAnalysisCard(eventId: eventId)
                    .padding(.horizontal)

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryStatCard(value: "\(drinkCount)",                  label: "Total Drinks",   icon: "wineglass.fill",   color: AppColors.accent)
                    SummaryStatCard(value: "\(Int(calories))",               label: "Drink Cals",      icon: "flame.fill",       color: .orange)
                    SummaryStatCard(value: String(format: "%.1f", standardDrinks), label: "Std Drinks", icon: "drop.fill",       color: AppColors.textSecondary)
                    SummaryStatCard(value: String(format: "%.1fg", alcoholG),label: "Alcohol",         icon: "flask.fill",       color: AppColors.textSecondary)
                }
                .padding(.horizontal)

                // Drinking pace history card
                if eventEntries.count >= 2 {
                    DrinkingPaceHistoryCard(
                        entries: eventEntries,
                        drinkTypes: appState.allDrinkTypes
                    )
                    .padding(.horizontal)
                }

                // Mean BAC card
                if meanBACValue > 0 {
                    VStack(spacing: 10) {
                        HStack {
                            Label("Mean BAC", systemImage: "waveform.path.ecg")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Text(meanBACStage.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(meanBACStage.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(meanBACStage.color.opacity(0.12))
                                .cornerRadius(8)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%.3f%%", meanBACValue))
                                .font(.system(size: 34, weight: .black, design: .monospaced))
                                .foregroundStyle(meanBACStage.color)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("avg BAC during event")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.textSecondary)
                                Text("not peak · not lowest")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding()
                    .background(meanBACStage.color.opacity(0.07))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(meanBACStage.color.opacity(0.22), lineWidth: 1))
                    .padding(.horizontal)
                }

                // Recovery projection
                if peakBAC > 0 {
                    RecoveryProjectionCard(
                        peakBAC: peakBAC,
                        peakTime: timeline.max(by: { $0.bac < $1.bac })?.date ?? event.startTime
                    )
                }

                if event.drivingMode {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "car.fill")
                                .foregroundStyle(AppColors.danger)
                            Text("Driving Mode")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                            Spacer()
                        }
                        HStack {
                            Text("Peak BAC")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            Text(String(format: "%.3f%%", peakBAC))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(IntoxicationStage.stage(for: peakBAC).color)
                        }
                        if peakBAC > 0 {
                            HStack {
                                Text("Time to zero BAC")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textSecondary)
                                Spacer()
                                let h = Int(hoursToZero)
                                let m = Int((hoursToZero - Double(h)) * 60)
                                Text("~\(h)h \(m)m")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.text)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }

                // Drink breakdown
                if !drinkBreakdown(entries: eventEntries).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Breakdown")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                        ForEach(drinkBreakdown(entries: eventEntries), id: \.0) { name, count in
                            HStack {
                                Text(name)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                                Spacer()
                                Text("×\(count)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }

                // Event timeline (drinks, water, food sorted by time)
                let sipDurations = drinkSipDurations(entries: eventEntries, drinkTypes: appState.allDrinkTypes)
                let sipDurMap: [String: Int] = Dictionary(uniqueKeysWithValues: sipDurations.map { ($0.entry.id, $0.sipMinutes) })
                let allTimestamps: [(date: Date, label: String)] = {
                    var items: [(Date, String)] = []
                    for e in eventEntries {
                        let name = appState.allDrinkTypes.first { $0.id == e.drinkTypeId }?.name ?? "Drink"
                        let base = e.quantity > 1 ? "×\(e.quantity) \(name)" : name
                        let sip  = sipDurMap[e.id].map { " · ~\($0)m" } ?? ""
                        items.append((e.timestamp, base + sip))
                    }
                    for w in eventWater {
                        items.append((w.timestamp, "💧 Water"))
                    }
                    for f in eventFood {
                        items.append((f.timestamp, "\(f.type.emoji) \(f.type.displayName)"))
                    }
                    return items.sorted { $0.0 < $1.0 }
                }()
                if !allTimestamps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Timeline", systemImage: "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                        ForEach(allTimestamps.indices, id: \.self) { idx in
                            let item = allTimestamps[idx]
                            HStack {
                                Text(item.label)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                                Spacer()
                                Text(item.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            if idx < allTimestamps.count - 1 {
                                Divider().background(AppColors.border)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }

                // Calorie equivalencies (Pro)
                if appState.isPro && calories > 0 {
                    CalorieEquivalenciesCard(calories: calories)
                }

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Notes", systemImage: "note.text")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        if notesSavedAt != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text("Saved")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(AppColors.success)
                        }
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(AppColors.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                        .foregroundStyle(AppColors.text)
                        .onChange(of: notes) { _, newVal in
                            appState.updateEventNotes(id: eventId, notes: newVal)
                            notesSavedAt = Date()
                        }
                }
                .padding(.horizontal)

                // Delete
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete Night")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.dangerDim)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(AppColors.background)
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    // Share card (image)
                    Button {
                        let card = SummaryShareCard(
                            event: event,
                            meanBAC: meanBACValue,
                            drinkCount: drinkCount,
                            standardDrinks: standardDrinks,
                            timeline: timeline,
                            calories: calories,
                            waterCount: eventWater.count
                        ).environment(\.colorScheme, .dark)
                        let renderer = ImageRenderer(content: card)
                        renderer.proposedSize = .init(width: 390, height: 693)
                        renderer.scale = 3.0
                        guard let image = renderer.uiImage else { return }
                        let av = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            root.present(av, animated: true)
                        }
                    } label: {
                        Label("Share Night Card", systemImage: "square.and.arrow.up")
                    }

                    // Export PDF (Pro + report required)
                    if appState.isPro, let report = event.aiReport {
                        Button {
                            let reportData = NightReportData(
                                event: event,
                                report: report,
                                drinkCount: drinkCount,
                                peakBAC: peakBAC,
                                calories: calories,
                                waterCount: eventWater.count,
                                standardDrinks: standardDrinks,
                                userProfile: appState.userProfile
                            )
                            if let url = exportNightReportPDF(reportData) {
                                pdfURL = url
                                showPDFShare = true
                            }
                        } label: {
                            Label("Export Health Report (PDF)", systemImage: "doc.text.fill")
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.accent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    appState.updateEventNotes(id: eventId, notes: notes)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $showPDFShare) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            notes = event.notes ?? ""
            // Show interstitial when browsing past summaries (not triggered by endEvent which already fires one).
            // Uses the alternating method so it only fires every other visit.
            if appState.pendingSummaryEventId != eventId {
                AdManager.shared.showInterstitialForBrowse(isPro: appState.isPro)
            }
        }
        .confirmationDialog("Delete this night?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                appState.deleteEvent(eventId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func nightProse(event: NightEvent, drinkCount: Int, calories: Double, alcoholG: Double, peakBAC: Double) -> String {
        let duration = event.duration
        let h = Int(duration / 3600)
        let m = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        let durationStr = h > 0 ? "\(h)h \(m)m" : "\(m)m"

        var sentence = "You had \(drinkCount) drink\(drinkCount == 1 ? "" : "s") over \(durationStr)"

        if peakBAC > 0 {
            sentence += ", peaking at \(String(format: "%.3f%%", peakBAC)) BAC"
        }

        if calories > 50 {
            let pizza = calories / 285.0
            sentence += ". That's \(Int(calories)) calories — about \(String(format: "%.1f", pizza)) slice\(pizza < 1.5 ? "" : "s") of pizza"
        }

        if event.drivingMode {
            let limit = event.bacLimit ?? 0.08
            if peakBAC > limit {
                sentence += ". Your peak BAC exceeded the driving limit — good call not getting behind the wheel"
            } else if peakBAC > 0 {
                sentence += ". You stayed under the driving limit all night"
            }
        }

        return sentence + "."
    }

    private func drinkBreakdown(entries: [DrinkEntry]) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in entries {
            let name = appState.allDrinkTypes.first { $0.id == e.drinkTypeId }?.name ?? "Unknown"
            counts[name, default: 0] += e.quantity
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private func eventDateRange(_ event: NightEvent) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        let start = f.string(from: event.startTime)
        if let end = event.endTime {
            f.dateStyle = .none
            return "\(start) – \(f.string(from: end))"
        }
        return start
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let h = Int(interval / 3600)
        let m = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(h)h \(m)m"
    }
}

private struct SummaryStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }
}

private struct BACChartView: View {
    let points: [BACDataPoint]
    let peakBAC: Double
    let drivingLimit: Double?
    let eventEndTime: Date?

    private var yMax: Double {
        let dataMax = points.map(\.bac).max() ?? 0
        let limitMax = (drivingLimit ?? 0) * 1.15
        return max(dataMax * 1.18, limitMax, 0.04)
    }

    private var peakPoint: BACDataPoint? {
        points.max(by: { $0.bac < $1.bac }).flatMap { $0.bac > 0.001 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("BAC Timeline", systemImage: "waveform.path.ecg")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            Chart {
                ForEach(points) { p in
                    AreaMark(
                        x: .value("Time", p.date),
                        yStart: .value("Zero", 0),
                        yEnd: .value("BAC", p.bac)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.accent.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }
                ForEach(points) { p in
                    LineMark(
                        x: .value("Time", p.date),
                        y: .value("BAC", p.bac)
                    )
                    .foregroundStyle(AppColors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
                if let limit = drivingLimit {
                    RuleMark(y: .value("Limit", limit))
                        .foregroundStyle(AppColors.danger.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text(String(format: "%.2f%%", limit))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(AppColors.danger)
                                .padding(.horizontal, 3)
                        }
                }
                if let endTime = eventEndTime {
                    RuleMark(x: .value("Ended", endTime))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                if let peak = peakPoint {
                    PointMark(
                        x: .value("Time", peak.date),
                        y: .value("BAC", peak.bac)
                    )
                    .foregroundStyle(IntoxicationStage.stage(for: peak.bac).color)
                    .symbolSize(44)
                    .annotation(position: .top, alignment: .center) {
                        Text(String(format: "%.3f%%", peak.bac))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(IntoxicationStage.stage(for: peak.bac).color)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                    AxisValueLabel {
                        if let bac = value.as(Double.self) {
                            Text(String(format: "%.2f", bac))
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...yMax)
            .frame(height: 180)
            .overlay(alignment: .topTrailing) {
                if let endTime = eventEndTime {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Finished")
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.2)
                        Text(endTime, format: .dateTime.hour().minute())
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(AppColors.surface.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(6)
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

private struct CalorieEquivalenciesCard: View {
    let calories: Double

    private func duration(_ calPerMin: Double) -> String {
        let minutes = calories / calPerMin
        let h = Int(minutes / 60)
        let m = Int(minutes.truncatingRemainder(dividingBy: 60))
        return h > 0 ? "\(h)h \(m)m" : "\(Int(minutes))m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Calorie Breakdown", systemImage: "flame.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            // Sports section
            VStack(alignment: .leading, spacing: 8) {
                Text("BURN IT OFF")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textTertiary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    CalSportCell(icon: "figure.run",          label: "Running",  value: duration(10))
                    CalSportCell(icon: "figure.outdoor.cycle", label: "Cycling",  value: duration(8))
                    CalSportCell(icon: "figure.pool.swim",    label: "Swimming", value: duration(7))
                    CalSportCell(icon: "figure.walk",         label: "Walking",  value: duration(4.5))
                }
            }

            Divider().background(AppColors.border)

            // Food section
            VStack(alignment: .leading, spacing: 8) {
                Text("FOOD EQUIVALENT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.textTertiary)

                HStack(spacing: 0) {
                    CalFoodCell(emoji: "🍕", value: String(format: "%.1f", calories / 285), label: "pizza\nslices")
                    CalFoodCell(emoji: "🍔", value: String(format: "%.1f", calories / 354), label: "big\nburgers")
                    CalFoodCell(emoji: "🍟", value: String(format: "%.1f", calories / 150), label: "chips\nbags")
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .padding(.horizontal)
    }
}

private struct CalSportCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColors.text)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(AppColors.background)
        .cornerRadius(10)
    }
}

private struct CalFoodCell: View {
    let emoji: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 26))
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DrinkingPaceCard: View {
    let entries: [DrinkEntry]
    let waterEntries: [WaterEntry]
    let timeline: [BACDataPoint]
    let eventStart: Date
    let eventEnd: Date?

    private struct BarItem: Identifiable {
        let id = UUID()
        let hourStart: Date
        let category: String
        let count: Double
    }

    private struct BACDot: Identifiable {
        let id: Int
        let hourStart: Date
        let scaled: Double
    }

    private var chartData: ([BarItem], [BACDot]) {
        let end = eventEnd ?? timeline.last?.date ?? eventStart.addingTimeInterval(3600)
        let totalHours = max(1, Int(ceil(end.timeIntervalSince(eventStart) / 3600)))
        let peakBAC = max(timeline.map(\.bac).max() ?? 0, 0.001)

        var bars: [BarItem] = []
        var maxCount: Double = 1

        for h in 0..<totalHours {
            let hStart = eventStart.addingTimeInterval(Double(h) * 3600)
            let hEnd = hStart.addingTimeInterval(3600)

            let drinkCount = Double(entries
                .filter { $0.timestamp >= hStart && $0.timestamp < hEnd }
                .reduce(0) { $0 + $1.quantity })
            let waterCount = Double(waterEntries
                .filter { $0.timestamp >= hStart && $0.timestamp < hEnd }
                .count)

            if drinkCount > 0 { bars.append(BarItem(hourStart: hStart, category: "Drinks", count: drinkCount)) }
            if waterCount > 0 { bars.append(BarItem(hourStart: hStart, category: "Water", count: waterCount)) }
            maxCount = max(maxCount, drinkCount + waterCount)
        }

        let dots: [BACDot] = (0..<totalHours).map { h in
            let hStart = eventStart.addingTimeInterval(Double(h) * 3600)
            let mid = hStart.addingTimeInterval(1800)
            let bac = timeline.min(by: {
                abs($0.date.timeIntervalSince(mid)) < abs($1.date.timeIntervalSince(mid))
            })?.bac ?? 0
            return BACDot(id: h, hourStart: hStart, scaled: bac / peakBAC * maxCount)
        }

        return (bars, dots)
    }

    var body: some View {
        let (bars, bacDots) = chartData
        VStack(alignment: .leading, spacing: 10) {
            Label("Drinking Pace", systemImage: "chart.bar.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            Chart {
                ForEach(bars) { item in
                    BarMark(
                        x: .value("Hour", item.hourStart, unit: .hour),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(by: .value("Type", item.category))
                    .cornerRadius(3)
                }
                ForEach(bacDots) { dot in
                    LineMark(
                        x: .value("Hour", dot.hourStart, unit: .hour),
                        y: .value("BAC", dot.scaled)
                    )
                    .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .interpolationMethod(.monotone)
                }
            }
            .chartForegroundStyleScale(["Drinks": AppColors.accent, "Water": AppColors.water])
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                    AxisValueLabel {
                        if let n = val.as(Double.self) {
                            Text("\(Int(n))")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { val in
                    AxisGridLine().foregroundStyle(AppColors.border.opacity(0.4))
                    AxisValueLabel {
                        if let date = val.as(Date.self) {
                            Text(date, format: .dateTime.hour())
                                .font(.system(size: 9))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 130)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColors.accent).frame(width: 10, height: 10)
                    Text("Drinks").font(.system(size: 10)).foregroundStyle(AppColors.textTertiary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(AppColors.water).frame(width: 10, height: 10)
                    Text("Water").font(.system(size: 10)).foregroundStyle(AppColors.textTertiary)
                }
                HStack(spacing: 4) {
                    Capsule().fill(AppColors.textSecondary.opacity(0.5)).frame(width: 14, height: 2)
                    Text("BAC curve").font(.system(size: 10)).foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

private struct RecoveryProjectionCard: View {
    let peakBAC: Double
    let peakTime: Date

    private struct Milestone: Identifiable {
        let id: Int
        let name: String
        let bac: Double
        let time: Date
        let color: Color
        var isPast: Bool { Date() > time }
    }

    private var milestones: [Milestone] {
        var raw: [(name: String, bac: Double, color: Color)] = []

        let peakStage = IntoxicationStage.stage(for: peakBAC)
        raw.append((name: peakStage.name, bac: peakBAC, color: peakStage.color))

        IntoxicationStage.all
            .filter { $0.maxBAC < peakBAC }
            .sorted { $0.maxBAC > $1.maxBAC }
            .forEach { raw.append((name: $0.name, bac: $0.maxBAC, color: $0.color)) }

        raw.append((name: "Zero", bac: 0, color: IntoxicationStage.all[0].color))

        return raw.enumerated().map { i, m in
            let hours = (peakBAC - m.bac) / 0.015
            return Milestone(id: i, name: m.name, bac: m.bac,
                             time: peakTime.addingTimeInterval(hours * 3600), color: m.color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Recovery Timeline", systemImage: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.bottom, 14)

            ForEach(milestones.indices, id: \.self) { idx in
                let m = milestones[idx]
                let isLast = idx == milestones.count - 1

                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(m.isPast ? m.color.opacity(0.35) : m.color)
                            .frame(width: 9, height: 9)
                            .padding(.top, 3)
                        if !isLast {
                            let gap = milestones[idx + 1].time.timeIntervalSince(m.time)
                            let h = Int(gap / 3600)
                            let mn = Int((gap.truncatingRemainder(dividingBy: 3600)) / 60)
                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(AppColors.border.opacity(0.5))
                                    .frame(width: 1.5, height: 8)
                                Text(h > 0 ? "\(h)h \(mn)m" : "\(mn)m")
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppColors.textTertiary)
                                Rectangle()
                                    .fill(AppColors.border.opacity(0.5))
                                    .frame(width: 1.5, height: 8)
                            }
                        }
                    }
                    .frame(width: 32, alignment: .center)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(m.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(m.isPast ? AppColors.textSecondary : m.color)
                                if m.isPast {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppColors.success)
                                }
                            }
                            if m.bac > 0 {
                                Text(String(format: "%.3f%%", m.bac))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        Spacer()
                        Text(m.time, format: .dateTime.hour().minute())
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(m.isPast ? AppColors.textTertiary : AppColors.text)
                    }
                    .padding(.top, 1)
                    .padding(.bottom, isLast ? 0 : 14)
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - Share Card

private struct SummaryShareCard: View {
    let event: NightEvent
    let meanBAC: Double
    let drinkCount: Int
    let standardDrinks: Double
    let timeline: [BACDataPoint]
    let calories: Double
    let waterCount: Int

    private let cardW: CGFloat = 390
    private let cardH: CGFloat = 693

    private var stage: IntoxicationStage { IntoxicationStage.stage(for: meanBAC) }
    private var peakBAC: Double { timeline.map(\.bac).max() ?? meanBAC }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: event.startTime)
    }

    private var durationStr: String {
        let d = event.duration
        let h = Int(d / 3600)
        let m = Int(d.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var hourlyData: [(label: String, bac: Double)] {
        guard !timeline.isEmpty else { return [] }
        let sorted = timeline.sorted { $0.date < $1.date }
        let start = event.startTime
        let end = event.endTime ?? sorted.last!.date
        let totalHours = max(Int(ceil(end.timeIntervalSince(start) / 3600)), 1)
        let fmt = DateFormatter()
        fmt.dateFormat = "ha"
        return (0...totalHours).map { h in
            let t = start.addingTimeInterval(Double(h) * 3600)
            let bac = interpolatedBAC(at: t, sorted: sorted)
            return (label: fmt.string(from: t).lowercased(), bac: max(0, bac))
        }
    }

    private func interpolatedBAC(at time: Date, sorted: [BACDataPoint]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        if time <= sorted.first!.date { return sorted.first!.bac }
        if time >= sorted.last!.date { return sorted.last!.bac }
        for i in 0..<(sorted.count - 1) {
            if sorted[i].date <= time && time <= sorted[i + 1].date {
                let span = sorted[i + 1].date.timeIntervalSince(sorted[i].date)
                guard span > 0 else { return sorted[i].bac }
                let frac = time.timeIntervalSince(sorted[i].date) / span
                return sorted[i].bac + (sorted[i + 1].bac - sorted[i].bac) * frac
            }
        }
        return 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.04, green: 0.04, blue: 0.07)
                .ignoresSafeArea()

            // Top stage-color sunrise wash
            LinearGradient(
                colors: [stage.color.opacity(0.40), stage.color.opacity(0.08), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)

            VStack(spacing: 0) {
                // Branding row
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "wineglass.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                        Text("TRACKSIP")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2.5)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    Text(formattedDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 28)
                .padding(.top, 54)

                Spacer().frame(height: 22)

                // Event name
                Text(event.displayName)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)

                Text("\(durationStr) night out")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 3)

                Spacer().frame(height: 26)

                // Hero BAC
                ZStack {
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [stage.color.opacity(0.55), .clear],
                            center: .center, startRadius: 0, endRadius: 88
                        ))
                        .frame(width: 210, height: 105)
                        .blur(radius: 28)

                    VStack(spacing: 5) {
                        Text(String(format: "%.3f%%", meanBAC))
                            .font(.system(size: 60, weight: .black, design: .monospaced))
                            .foregroundStyle(stage.color)
                            .shadow(color: stage.color.opacity(0.8), radius: 24, x: 0, y: 0)

                        Text("MEAN BAC  ·  " + stage.name.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(2)
                            .foregroundStyle(stage.color.opacity(0.65))
                    }
                }

                Spacer().frame(height: 28)

                // Hourly BAC chart section
                VStack(alignment: .leading, spacing: 8) {
                    Text("YOUR NIGHT, HOUR BY HOUR")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.leading, 2)

                    ShareHourlyChart(data: hourlyData, peakBAC: peakBAC)
                        .frame(height: 144)
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 22)

                // Stats pill
                HStack(spacing: 0) {
                    ShareMiniStat(emoji: "🍹", value: "\(drinkCount)", label: "drinks")
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                    ShareMiniStat(emoji: "🔥", value: "\(Int(calories))", label: "cal")
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                    ShareMiniStat(emoji: "💧", value: "\(waterCount)", label: "water")
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 36)
                    ShareMiniStat(emoji: "🥃", value: String(format: "%.1f", standardDrinks), label: "std")
                }
                .padding(.vertical, 16)
                .background(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 24)

                Spacer()

                Text("tracked with TrackSip")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.15))
                    .padding(.bottom, 46)
            }
        }
        .frame(width: cardW, height: cardH)
    }
}

private struct ShareHourlyChart: View {
    let data: [(label: String, bac: Double)]
    let peakBAC: Double

    private var peakIdx: Int? {
        data.indices.max(by: { data[$0].bac < data[$1].bac })
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let n = max(data.count, 1)
                let gap: CGFloat = 4
                let barW = (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
                let yMax = max(peakBAC * 1.15, 0.01)
                let chartH = geo.size.height

                ZStack(alignment: .bottomLeading) {
                    // Grid lines
                    Canvas { ctx, size in
                        for frac in [CGFloat(0.25), 0.50, 0.75] {
                            let y = size.height * (1 - frac)
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bars
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(0..<n, id: \.self) { i in
                            let item = data[i]
                            let stg = IntoxicationStage.stage(for: item.bac)
                            let barH = max(CGFloat(item.bac / yMax) * chartH, item.bac > 0 ? 3 : 0)

                            ZStack(alignment: .top) {
                                RoundedRectangle(cornerRadius: min(barW * 0.35, 5))
                                    .fill(LinearGradient(
                                        colors: [stg.color, stg.color.opacity(0.45)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(width: barW, height: barH)

                                if barH > 10 {
                                    RoundedRectangle(cornerRadius: min(barW * 0.35, 5))
                                        .fill(.white.opacity(0.12))
                                        .frame(width: barW, height: min(barH * 0.35, 14))
                                }
                            }
                            .frame(width: barW, height: barH)
                            .overlay(alignment: .top) {
                                if i == peakIdx && item.bac > 0 {
                                    Text(String(format: "%.3f", item.bac))
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(stg.color)
                                        .offset(y: -13)
                                }
                            }
                        }
                    }
                }
            }

            // Hour labels
            HStack(spacing: 4) {
                ForEach(0..<data.count, id: \.self) { i in
                    Text(data[i].label)
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        }
    }
}

private struct ShareMiniStat: View {
    let emoji: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(emoji)
                .font(.system(size: 16))
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Drinking Pace helper + card

/// Per-drink sipping duration: min(effectiveDrinkingMinutes, gap to next drink).
struct DrinkSipResult {
    let entry: DrinkEntry
    let drinkType: DrinkType?
    let sipMinutes: Int
}

func drinkSipDurations(entries: [DrinkEntry], drinkTypes: [DrinkType]) -> [DrinkSipResult] {
    let sorted = entries.sorted { $0.timestamp < $1.timestamp }
    return sorted.enumerated().map { i, entry in
        let dt      = drinkTypes.first { $0.id == entry.drinkTypeId }
        let natural = dt?.effectiveDrinkingMinutes ?? 20
        let sipMin: Int
        if i + 1 < sorted.count {
            let gap = Int(sorted[i + 1].timestamp.timeIntervalSince(entry.timestamp) / 60)
            sipMin = gap > 0 ? min(natural, gap) : natural
        } else {
            sipMin = natural
        }
        return DrinkSipResult(entry: entry, drinkType: dt, sipMinutes: sipMin)
    }
}

private struct DrinkingPaceHistoryCard: View {
    let entries: [DrinkEntry]
    let drinkTypes: [DrinkType]

    private var sips: [DrinkSipResult] { drinkSipDurations(entries: entries, drinkTypes: drinkTypes) }

    private var avgSip: Double {
        let total = sips.reduce(0) { $0 + $1.sipMinutes }
        return sips.isEmpty ? 0 : Double(total) / Double(sips.count)
    }
    private var durationHours: Double {
        guard let first = entries.min(by: { $0.timestamp < $1.timestamp }),
              let last  = entries.max(by: { $0.timestamp < $1.timestamp }) else { return 0 }
        return max(0.01, last.timestamp.timeIntervalSince(first.timestamp) / 3600)
    }
    private var drinksPerHour: Double {
        Double(entries.reduce(0) { $0 + $1.quantity }) / durationHours
    }
    private var paceLabel: String {
        if avgSip < 12 { return "Fast" }
        if avgSip < 25 { return "Moderate" }
        return "Slow"
    }
    private var paceColor: Color {
        if avgSip < 12 { return AppColors.danger }
        if avgSip < 25 { return AppColors.accent }
        return AppColors.success
    }
    private var fastest: DrinkSipResult? { sips.min(by: { $0.sipMinutes < $1.sipMinutes }) }
    private var slowest: DrinkSipResult? { sips.max(by: { $0.sipMinutes < $1.sipMinutes }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Drinking Pace", systemImage: "gauge.with.needle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: 8) {
                ForEach(["Fast", "Moderate", "Slow"], id: \.self) { label in
                    let active = label == paceLabel
                    Text(label)
                        .font(.system(size: 11, weight: active ? .bold : .regular))
                        .foregroundStyle(active ? paceColor : AppColors.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(active ? paceColor.opacity(0.15) : AppColors.surface)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(active ? paceColor.opacity(0.4) : AppColors.border, lineWidth: 1))
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f min", avgSip))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.text)
                    Text("avg per drink")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
                Divider().frame(height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f/hr", drinksPerHour))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.text)
                    Text("drinks per hour")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if let f = fastest, let s = slowest, f.entry.id != s.entry.id {
                Divider().background(AppColors.border)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FASTEST")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(AppColors.danger.opacity(0.8))
                        Text("\(f.drinkType?.name ?? "Drink") (~\(f.sipMinutes)m)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SLOWEST")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(AppColors.success.opacity(0.8))
                        Text("\(s.drinkType?.name ?? "Drink") (~\(s.sipMinutes)m)")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.text)
                    }
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }
}
