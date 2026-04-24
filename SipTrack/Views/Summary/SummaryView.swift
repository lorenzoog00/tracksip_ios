import SwiftUI

struct SummaryView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var notes = ""
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
        let durationH = event.duration / 3600
        let hoursToZero = BACCalculator.hoursToZeroBAC(peakBAC)

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
                    Label("Notes", systemImage: "note.text")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(AppColors.surface)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                        .foregroundStyle(AppColors.text)
                        .onChange(of: notes) { _, newVal in
                            appState.updateEventNotes(id: eventId, notes: newVal)
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
        .onAppear { notes = event.notes ?? "" }
        .confirmationDialog("Delete this night?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                appState.deleteEvent(eventId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
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
