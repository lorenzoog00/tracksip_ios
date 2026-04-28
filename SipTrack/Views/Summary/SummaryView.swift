import SwiftUI
import Charts

struct SummaryView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var notes = ""
    @State private var notesSavedAt: Date? = nil
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    private var event: NightEvent?      { appState.events.first { $0.id == eventId } }
    private var eventEntries: [DrinkEntry] { appState.entries.filter { $0.eventId == eventId } }
    private var eventWater: [WaterEntry]   { appState.waterEntries.filter { $0.eventId == eventId } }

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
        let drivingLimit: Double? = event.drivingMode ? (event.bacLimit ?? appState.userProfile.bacLimit) : nil

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
                }
                .padding(.top)

                // BAC timeline chart
                if !timeline.isEmpty {
                    BACChartView(
                        points: timeline,
                        drinkTimestamps: eventEntries.map(\.timestamp),
                        peakBAC: peakBAC,
                        drivingLimit: drivingLimit
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

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SummaryStatCard(value: "\(drinkCount)",                  label: "Total Drinks",   icon: "wineglass.fill",   color: AppColors.accent)
                    SummaryStatCard(value: "\(Int(calories))",               label: "Calories",        icon: "flame.fill",       color: .orange)
                    SummaryStatCard(value: String(format: "%.1f", standardDrinks), label: "Std Drinks", icon: "drop.fill",       color: AppColors.textSecondary)
                    SummaryStatCard(value: String(format: "%.1fg", alcoholG),label: "Alcohol",         icon: "flask.fill",       color: AppColors.textSecondary)
                }
                .padding(.horizontal)

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
                ShareLink(item: shareText) {
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
        .onAppear { notes = event.notes ?? "" }
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
    let drinkTimestamps: [Date]
    let peakBAC: Double
    let drivingLimit: Double?

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
                ForEach(drinkTimestamps.indices, id: \.self) { i in
                    RuleMark(x: .value("Drink", drinkTimestamps[i]))
                        .foregroundStyle(AppColors.accent.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
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

    private var equivalencies: [(String, String)] {
        [
            ("🍕", "\(String(format: "%.1f", calories / 285)) slices of pizza"),
            ("🍺", "\(Int(calories / 153)) beers worth of calories"),
            ("🚶", "\(Int(calories / 4.5)) minutes of walking"),
            ("🏃", "\(Int(calories / 10)) minutes of running"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Calorie Equivalencies", systemImage: "chart.bar.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            ForEach(equivalencies, id: \.0) { emoji, text in
                HStack(spacing: 8) {
                    Text(emoji)
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.text)
                }
            }
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .padding(.horizontal)
    }
}
