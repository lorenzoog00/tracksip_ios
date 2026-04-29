import SwiftUI

struct ActiveEventView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showEndConfirm     = false
    @State private var showEditEntry: DrinkEntry? = nil
    @State private var timer: Timer?      = nil
    @State private var now                = Date()

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var eventEntries: [DrinkEntry] { appState.entries.filter { $0.eventId == eventId }.sorted { $0.timestamp > $1.timestamp } }
    private var eventWater: [WaterEntry]  { appState.waterEntries.filter { $0.eventId == eventId }.sorted { $0.timestamp > $1.timestamp } }
    private var currentBAC: Double {
        _ = now
        return appState.currentBAC(for: eventId)
    }
    private var stage: IntoxicationStage  { IntoxicationStage.stage(for: currentBAC) }

    var body: some View {
        if let event = event {
            content(event: event)
        } else {
            Text("Event not found")
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func content(event: NightEvent) -> some View {
        let bacLimit = event.bacLimit ?? appState.userProfile.bacLimit
        let overLimit = event.drivingMode && currentBAC >= bacLimit

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 16) {

                    // DO NOT DRIVE banner
                    if overLimit {
                        DriveWarningBanner(bac: currentBAC, bacLimit: bacLimit)
                    }

                    // BAC Hero
                    BACHero(
                        bac: currentBAC,
                        stage: stage,
                        event: event,
                        now: now,
                        drivingMode: event.drivingMode,
                        bacLimit: bacLimit
                    )

                    // Stats row
                    StatsRow(eventId: eventId, waterEntries: eventWater)

                    // Quick Add — inline, always visible
                    QuickAddGrid(eventId: eventId, drinkTypes: appState.allDrinkTypes)

                    // Drink breakdown chips (summary of what was had)
                    if !eventEntries.isEmpty {
                        DrinkChips(entries: eventEntries, drinkTypes: appState.allDrinkTypes)
                    }

                    // Timeline
                    if !eventEntries.isEmpty || !eventWater.isEmpty {
                        TimelineSection(
                            entries: eventEntries,
                            waterEntries: eventWater,
                            drinkTypes: appState.allDrinkTypes,
                            onDeleteEntry: { appState.deleteEntry($0) },
                            onDeleteWater: { appState.deleteWaterEntry($0) },
                            onEditEntry: { showEditEntry = $0 }
                        )
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.top)
            }
            .background(AppColors.background)

            // Bottom bar — water + end only (drinks are inline above)
            BottomBar(
                onAddWater: { appState.addWater(eventId: eventId) },
                onEnd:      { showEndConfirm = true }
            )

            // Top toast — slides in from above when a drink or water is added
            VStack {
                if let undoEntry = appState.undoEntry, undoEntry.eventId == eventId {
                    let dt = appState.allDrinkTypes.first { $0.id == undoEntry.drinkTypeId }
                    DrinkToast(
                        drinkName: dt?.name ?? "Drink",
                        symbol: dt?.sfSymbol ?? "cup.and.saucer.fill",
                        onUndo: { appState.undoLastEntry() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if let waterEntry = appState.undoWaterEntry, waterEntry.eventId == eventId {
                    WaterToast(volumeMl: Int(waterEntry.volumeMl), onUndo: { appState.undoLastWaterEntry() })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.72), value: appState.undoEntry?.id ?? appState.undoWaterEntry?.id)
            .zIndex(10)
        }
        .navigationTitle(event.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .onAppear  { startTimer() }
        .onDisappear { stopTimer() }
        .sheet(item: $showEditEntry) { entry in
            EditEntryView(entry: entry)
        }
        .confirmationDialog("End this night?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Night", role: .destructive) {
                appState.endEvent(eventId)
                appState.pendingSummaryEventId = eventId
            }
            Button("Cancel", role: .cancel) {}
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
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in now = Date() }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - DO NOT DRIVE

private struct DriveWarningBanner: View {
    let bac: Double
    let bacLimit: Double

    private var hoursRemaining: Double {
        max(0, (bac - bacLimit) / 0.015)
    }

    var body: some View {
        let h = Int(hoursRemaining)
        let m = Int((hoursRemaining - Double(h)) * 60)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("DO NOT DRIVE")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(0.5)
                Spacer()
                Text(String(format: "%.3f%%", bac))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.danger.opacity(0.6))
            }
            .foregroundStyle(AppColors.danger)

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                if h > 0 {
                    Text("\(h)")
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                    Text("h ")
                        .font(.system(size: 20, weight: .medium))
                        .padding(.bottom, 4)
                }
                Text("\(m)")
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                Text("m")
                    .font(.system(size: 20, weight: .medium))
                    .padding(.bottom, 4)
                Spacer()
                Text("until safe\nto drive")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.danger.opacity(0.6))
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(2)
            }
            .foregroundStyle(AppColors.danger)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppColors.danger.opacity(0.1))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.danger.opacity(0.35), lineWidth: 1))
        .padding(.horizontal)
    }
}

// MARK: - BAC Hero

private struct BACHero: View {
    let bac: Double
    let stage: IntoxicationStage
    let event: NightEvent
    let now: Date
    let drivingMode: Bool
    let bacLimit: Double

    var body: some View {
        VStack(spacing: 12) {
            // Ambient glow orb behind the number
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [stage.color.opacity(0.22), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 200, height: 100)
                    .blur(radius: 12)

                Text(String(format: "%.3f%%", bac))
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(stage.color)
                    .shadow(color: stage.color.opacity(0.45), radius: 14, y: 0)
            }

            Text(stage.name)
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(stage.color.opacity(0.85))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(AppColors.border)
                        .frame(height: 7)
                        .frame(maxHeight: .infinity, alignment: .center)

                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [stage.color.opacity(0.7), stage.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * IntoxicationStage.barPosition(for: bac), height: 7)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: bac)

                    if drivingMode {
                        let tickX = geo.size.width * IntoxicationStage.barPosition(for: bacLimit)
                        Capsule()
                            .fill(AppColors.danger)
                            .frame(width: 2.5, height: 20)
                            .offset(x: max(0, tickX - 1.25))
                    }
                }
            }
            .frame(height: 20)
            .padding(.horizontal)

            if drivingMode {
                HStack(spacing: 4) {
                    Capsule()
                        .fill(AppColors.danger)
                        .frame(width: 8, height: 2)
                    Text(String(format: "limit %.2f%%", bacLimit))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.danger.opacity(0.7))
                }
            }

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
        .premiumCard(
            radius: 20,
            tint: stage.color,
            tintOpacity: 0.05,
            borderTop: stage.color.opacity(0.4),
            borderBottom: stage.color.opacity(0.06)
        )
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.4), value: stage.name)
    }
}

// MARK: - Stats Row

private struct StatsRow: View {
    @EnvironmentObject var appState: AppState
    let eventId: String
    let waterEntries: [WaterEntry]

    var body: some View {
        let entries = appState.entries.filter { $0.eventId == eventId }
        let drinks = entries.reduce(0) { $0 + $1.quantity }
        let calories = appState.totalCalories(for: eventId)
        let hydration = BACCalculator.hydrationLevel(waterEntries: waterEntries, drinkCount: drinks)
        let alcoholG = entries.reduce(0.0) { sum, e in
            let dt = appState.allDrinkTypes.first { $0.id == e.drinkTypeId }
            let vol = e.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = e.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + BACCalculator.calculateAlcohol(volumeMl: vol, abv: abv, quantity: e.quantity)
        }
        let stdDrinks = BACCalculator.standardDrinks(alcoholGrams: alcoholG)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatCell(value: "\(drinks)", label: "Drinks", icon: "wineglass.fill", color: AppColors.accent)
                Divider().frame(height: 40).background(AppColors.border)
                StatCell(value: "\(Int(calories))", label: "Calories", icon: "flame.fill", color: .orange)
                Divider().frame(height: 40).background(AppColors.border)
                StatCell(value: hydrationLabel(hydration), label: "Hydration", icon: "drop.fill", color: hydrationColor(hydration))
            }
            .padding(.vertical, 12)

            if alcoholG > 0 {
                Divider().background(AppColors.border).padding(.horizontal, 16)
                HStack(spacing: 5) {
                    Text(String(format: "%.1fg alcohol", alcoholG))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "%.1f std drinks", stdDrinks))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.vertical, 8)
            }
        }
        .premiumCard(radius: 14)
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

// MARK: - Drink Chips

private struct DrinkChips: View {
    let entries: [DrinkEntry]
    let drinkTypes: [DrinkType]

    private var breakdown: [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in entries {
            let name = drinkTypes.first { $0.id == e.drinkTypeId }?.name ?? "Unknown"
            counts[name, default: 0] += e.quantity
        }
        return counts.sorted { $0.value > $1.value }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(breakdown, id: \.0) { name, count in
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.text)
                        Text("×\(count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(AppColors.surface)
                    .cornerRadius(20)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppColors.border, lineWidth: 1))
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Quick Add (inline drink grid)

private struct QuickAddGrid: View {
    @EnvironmentObject var appState: AppState
    let eventId: String
    let drinkTypes: [DrinkType]

    let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ADD")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(drinkTypes) { dt in
                    DrinkTile(drinkType: dt) {
                        appState.addDrink(eventId: eventId, drinkTypeId: dt.id)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct DrinkTile: View {
    let drinkType: DrinkType
    let onTap: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: drinkType.sfSymbol)
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.accent)
                Text(drinkType.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .premiumCard(radius: 14)
            .scaleEffect(pressed ? 0.93 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeInOut(duration: 0.1)) { pressed = true } }
            .onEnded   { _ in withAnimation(.easeInOut(duration: 0.15)) { pressed = false } }
        )
    }
}

// MARK: - Drink toast

private struct DrinkToast: View {
    let drinkName: String
    let symbol: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(drinkName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("added to your night")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button("Undo", action: onUndo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.accent.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.22), AppColors.accent.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(AppColors.accent.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: AppColors.accent.opacity(0.35), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct WaterToast: View {
    let volumeMl: Int
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.water.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "drop.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.water)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Water (\(volumeMl)ml)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("stay hydrated 💧")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button("Undo", action: onUndo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.water)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.water.opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [AppColors.water.opacity(0.22), AppColors.water.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(AppColors.water.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: AppColors.water.opacity(0.35), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Timeline

private struct TimelineSection: View {
    let entries: [DrinkEntry]
    let waterEntries: [WaterEntry]
    let drinkTypes: [DrinkType]
    let onDeleteEntry: (String) -> Void
    let onDeleteWater: (String) -> Void
    let onEditEntry: (DrinkEntry) -> Void

    private enum Item: Identifiable {
        case drink(DrinkEntry)
        case water(WaterEntry)
        var id: String {
            switch self { case .drink(let e): return e.id; case .water(let w): return w.id }
        }
        var timestamp: Date {
            switch self { case .drink(let e): return e.timestamp; case .water(let w): return w.timestamp }
        }
    }

    private var items: [Item] {
        (entries.map { Item.drink($0) } + waterEntries.map { Item.water($0) })
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIMELINE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal)

            ForEach(items) { item in
                switch item {
                case .drink(let e):
                    DrinkRow(
                        entry: e,
                        drinkType: drinkTypes.first { $0.id == e.drinkTypeId },
                        onDelete: { onDeleteEntry(e.id) },
                        onEdit: { onEditEntry(e) }
                    )
                    .padding(.horizontal)
                case .water(let w):
                    WaterRow(entry: w, onDelete: { onDeleteWater(w.id) })
                        .padding(.horizontal)
                }
            }
        }
    }
}

private struct DrinkRow: View {
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
                if let c = entry.comment, !c.isEmpty {
                    Text(c).font(.system(size: 12)).foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
            Text(Self.tf.string(from: entry.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .premiumCard(radius: 12)
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

private struct WaterRow: View {
    let entry: WaterEntry
    let onDelete: () -> Void
    private static let tf: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.water)
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
        .premiumCard(radius: 12)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}


// MARK: - Bottom Bar

private struct BottomBar: View {
    let onAddWater: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAddWater) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 15))
                    Text("Water")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.water)
                .frame(width: 110, height: 50)
                .background(AppColors.waterDim)
                .cornerRadius(12)
            }

            Button(action: onEnd) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                    Text("End Night")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppColors.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppColors.dangerDim)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
