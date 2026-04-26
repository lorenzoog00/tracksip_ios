import SwiftUI

struct ActiveEventView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showDrinkPicker    = false
    @State private var showEndConfirm     = false
    @State private var showEditEntry: DrinkEntry? = nil
    @State private var timer: Timer?      = nil
    @State private var now                = Date()
    @State private var navigateToSummary  = false

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var eventEntries: [DrinkEntry] { appState.entries.filter { $0.eventId == eventId }.sorted { $0.timestamp > $1.timestamp } }
    private var eventWater: [WaterEntry]  { appState.waterEntries.filter { $0.eventId == eventId }.sorted { $0.timestamp > $1.timestamp } }
    private var currentBAC: Double {
        _ = now
        return appState.currentBAC(for: eventId)
    }
    private var stage: IntoxicationStage  { IntoxicationStage.stage(for: currentBAC) }
    private var drinkCount: Int           { eventEntries.reduce(0) { $0 + $1.quantity } }

    var body: some View {
        guard let event = event else {
            return AnyView(Text("Event not found").foregroundStyle(AppColors.textSecondary))
        }
        return AnyView(content(event: event))
    }

    private func content(event: NightEvent) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 20) {
                    // BAC Hero
                    BACHero(bac: currentBAC, stage: stage, event: event, drinkCount: drinkCount, now: now)

                    // Stats row
                    StatsRow(eventId: eventId, waterEntries: eventWater)

                    // Undo banner
                    if let undoEntry = appState.undoEntry, undoEntry.eventId == eventId {
                        UndoBanner { appState.undoLastEntry() }
                    }

                    // Timeline
                    if !eventEntries.isEmpty || !eventWater.isEmpty {
                        TimelineView(
                            entries: eventEntries,
                            waterEntries: eventWater,
                            drinkTypes: appState.allDrinkTypes,
                            onDeleteEntry: { appState.deleteEntry($0) },
                            onDeleteWater: { appState.deleteWaterEntry($0) },
                            onEditEntry: { showEditEntry = $0 }
                        )
                    }

                    Color.clear.frame(height: 100)
                }
                .padding(.top)
            }
            .background(AppColors.background)

            // Bottom action bar
            BottomBar(
                onAddDrink: { showDrinkPicker = true },
                onAddWater: { appState.addWater(eventId: eventId) },
                onEnd:      { showEndConfirm  = true }
            )
        }
        .navigationTitle(event.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
        .sheet(isPresented: $showDrinkPicker) {
            DrinkPickerSheet(eventId: eventId)
        }
        .sheet(item: $showEditEntry) { entry in
            EditEntryView(entry: entry)
        }
        .confirmationDialog("End this night?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Night", role: .destructive) {
                appState.endEvent(eventId)
                navigateToSummary = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(isPresented: $navigateToSummary) {
            SummaryView(eventId: eventId)
        }
        .alert("⚠️ Heads Up", isPresented: Binding(
            get: { !appState.activeWarnings.isEmpty },
            set: { if !$0 { appState.dismissWarnings() } }
        )) {
            Button("Got it") { appState.dismissWarnings() }
        } message: {
            Text(appState.activeWarnings.map(\.message).joined(separator: "\n\n"))
        }
        .alert("💧 Stay Hydrated", isPresented: $appState.showWaterNudge) {
            Button("Add Water") {
                appState.addWater(eventId: eventId)
                appState.dismissWaterNudge()
            }
            Button("Skip", role: .cancel) { appState.dismissWaterNudge() }
        } message: {
            Text("You're falling behind on water. Add a glass?")
        }
    }

    private func startTimer() {
        now = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            now = Date()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Sub-components

private struct BACHero: View {
    let bac: Double
    let stage: IntoxicationStage
    let event: NightEvent
    let drinkCount: Int
    let now: Date

    var body: some View {
        VStack(spacing: 12) {
            Text(String(format: "%.3f%%", bac))
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(stage.color)

            Text(stage.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(stage.color)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.border)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stage.color)
                        .frame(width: geo.size.width * IntoxicationStage.barPosition(for: bac))
                }
                .frame(height: 8)
            }
            .frame(height: 8)
            .padding(.horizontal)

            Text(stage.blurb)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if bac > 0 {
                let hours = BACCalculator.hoursToZeroBAC(bac)
                let h = Int(hours)
                let m = Int((hours - Double(h)) * 60)
                Text("~\(h)h \(m)m to zero")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
        .cornerRadius(16)
        .padding(.horizontal)
    }
}

private struct StatsRow: View {
    @EnvironmentObject var appState: AppState
    let eventId: String
    let waterEntries: [WaterEntry]

    var body: some View {
        let entries = appState.entries.filter { $0.eventId == eventId }
        let drinks = entries.reduce(0) { $0 + $1.quantity }
        let calories = appState.totalCalories(for: eventId)
        let hydration = BACCalculator.hydrationLevel(waterEntries: waterEntries, drinkCount: drinks)

        HStack(spacing: 0) {
            StatCell(value: "\(drinks)", label: "Drinks", icon: "wineglass.fill", color: AppColors.accent)
            Divider().frame(height: 40).background(AppColors.border)
            StatCell(value: "\(Int(calories))", label: "Calories", icon: "flame.fill", color: Color.orange)
            Divider().frame(height: 40).background(AppColors.border)
            StatCell(value: hydrationLabel(hydration), label: "Hydration", icon: "drop.fill", color: hydrationColor(hydration))
        }
        .padding(.vertical, 12)
        .background(AppColors.surface)
        .cornerRadius(14)
        .padding(.horizontal)
    }

    private func hydrationLabel(_ h: BACCalculator.HydrationLevel) -> String {
        switch h {
        case .none: return "-"
        case .behind: return "Behind"
        case .balanced: return "OK"
        case .great: return "Great"
        }
    }

    private func hydrationColor(_ h: BACCalculator.HydrationLevel) -> Color {
        switch h {
        case .none, .behind: return AppColors.danger
        case .balanced: return AppColors.accent
        case .great: return AppColors.success
        }
    }
}

private struct StatCell: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct UndoBanner: View {
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text("Drink added")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.text)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.accent)
        }
        .padding(12)
        .background(AppColors.surfaceElevated)
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

private struct TimelineView: View {
    let entries: [DrinkEntry]
    let waterEntries: [WaterEntry]
    let drinkTypes: [DrinkType]
    let onDeleteEntry: (String) -> Void
    let onDeleteWater: (String) -> Void
    let onEditEntry: (DrinkEntry) -> Void

    private enum TimelineItem: Identifiable {
        case drink(DrinkEntry)
        case water(WaterEntry)

        var id: String {
            switch self {
            case .drink(let e): return e.id
            case .water(let w): return w.id
            }
        }
        var timestamp: Date {
            switch self {
            case .drink(let e): return e.timestamp
            case .water(let w): return w.timestamp
            }
        }
    }

    private var items: [TimelineItem] {
        let drinks = entries.map { TimelineItem.drink($0) }
        let water  = waterEntries.map { TimelineItem.water($0) }
        return (drinks + water).sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal)

            ForEach(items) { item in
                switch item {
                case .drink(let entry):
                    DrinkEntryRow(
                        entry: entry,
                        drinkType: drinkTypes.first { $0.id == entry.drinkTypeId },
                        onDelete: { onDeleteEntry(entry.id) },
                        onEdit: { onEditEntry(entry) }
                    )
                    .padding(.horizontal)
                case .water(let w):
                    WaterEntryRow(entry: w, onDelete: { onDeleteWater(w.id) })
                        .padding(.horizontal)
                }
            }
        }
    }
}

private struct DrinkEntryRow: View {
    let entry: DrinkEntry
    let drinkType: DrinkType?
    let onDelete: () -> Void
    let onEdit: () -> Void
    private static let tf: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: drinkType?.sfSymbol ?? "cup.and.saucer.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.quantity > 1 ? "\(entry.quantity)× " : "")\(drinkType?.name ?? "Unknown")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.text)
                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            Text(Self.tf.string(from: entry.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.surface)
        .cornerRadius(10)
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

private struct WaterEntryRow: View {
    let entry: WaterEntry
    let onDelete: () -> Void
    private static let tf: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.success)
                .frame(width: 32)
            Text("Water (\(Int(entry.volumeMl))ml)")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(Self.tf.string(from: entry.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.surface)
        .cornerRadius(10)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

private struct BottomBar: View {
    let onAddDrink: () -> Void
    let onAddWater: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAddDrink) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Drink")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent)
                .foregroundStyle(.black)
                .cornerRadius(12)
            }
            Button(action: onAddWater) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 18))
                    .frame(width: 50, height: 50)
                    .background(AppColors.successDim)
                    .foregroundStyle(AppColors.success)
                    .cornerRadius(12)
            }
            Button(action: onEnd) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18))
                    .frame(width: 50, height: 50)
                    .background(AppColors.dangerDim)
                    .foregroundStyle(AppColors.danger)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// Drink picker sheet
private struct DrinkPickerSheet: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(appState.allDrinkTypes) { dt in
                            Button {
                                appState.addDrink(eventId: eventId, drinkTypeId: dt.id)
                                dismiss()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: dt.sfSymbol)
                                        .font(.system(size: 24))
                                        .foregroundStyle(AppColors.accent)
                                    Text(dt.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.text)
                                    Text("\(Int(dt.defaultVolumeMl))ml · \(String(format: "%.1f", dt.defaultAbv))%")
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
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}
