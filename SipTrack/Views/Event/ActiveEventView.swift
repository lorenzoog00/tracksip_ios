import SwiftUI

struct ActiveEventView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showEndConfirm     = false
    @State private var showFoodSheet      = false
    @State private var showEditEntry: DrinkEntry? = nil
    @State private var pendingDrink: PendingDrinkWarning? = nil
    @State private var showStats          = false

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var eventEntries: [DrinkEntry] { appState.entries.filter { $0.eventId == eventId }.sorted { $0.timestamp > $1.timestamp } }
    private var eventWater: [WaterEntry]  { appState.waterEntries.filter { $0.eventId == eventId }.sorted { $0.timestamp > $1.timestamp } }
    var eventFood: [FoodEntry] { appState.foodEntries.filter { $0.eventId == eventId } }
    private var currentBAC: Double {
        _ = appState.bacTick
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
        let bacLimit = event.bacLimit ?? appState.userProfile.resolvedBACLimit
        let overLimit = event.drivingMode && currentBAC >= bacLimit

        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 16) {

                    // DO NOT DRIVE banner
                    if overLimit {
                        DriveWarningBanner(bac: currentBAC, bacLimit: bacLimit, beta: BACCalculator.eliminationRate(profile: appState.userProfile))
                    }

                    // BAC Hero
                    BACHero(
                        bac: currentBAC,
                        stage: stage,
                        event: event,
                        now: appState.bacTick,
                        drivingMode: event.drivingMode,
                        bacLimit: bacLimit
                    )

                    // Current drink in progress
                    CurrentDrinkCard(entries: eventEntries, drinkTypes: appState.allDrinkTypes, now: appState.bacTick)

                    // Ceiling reached nudge
                    if let target = event.targetBAC, currentBAC >= target {
                        TargetBACBanner(bac: currentBAC, target: target)
                    }

                    // Stats row
                    StatsRow(eventId: eventId, waterEntries: eventWater)

                    // Quick Add — inline, always visible
                    DrinkPickerList(event: event, drinkTypes: appState.allDrinkTypes) { dt in
                        handleDrinkTap(dt, event: event, bacLimit: bacLimit)
                    }

                    // Drink breakdown chips (summary of what was had)
                    if !eventEntries.isEmpty {
                        DrinkChips(entries: eventEntries, drinkTypes: appState.allDrinkTypes)
                    }

                    // Timeline
                    if !eventEntries.isEmpty || !eventWater.isEmpty || !eventFood.isEmpty {
                        TimelineSection(
                            entries: eventEntries,
                            waterEntries: eventWater,
                            foodEntries: eventFood,
                            drinkTypes: appState.allDrinkTypes,
                            onDeleteEntry: { appState.deleteEntry($0) },
                            onDeleteWater: { appState.deleteWaterEntry($0) }
                        )
                    }

                    BannerAdView()
                        .padding(.horizontal)

                    Color.clear.frame(height: 90)
                }
                .padding(.top)
            }
            .background(AppColors.background)

            // Bottom bar — water + food + end only (drinks are inline above)
            BottomBar(
                onAddWater: { appState.addWater(eventId: eventId) },
                onAddFood:  { showFoodSheet = true },
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showStats = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("STATS")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color(hex: "#5BC8FF"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#5BC8FF").opacity(0.12))
                    .cornerRadius(20)
                }
            }
        }
        .sheet(item: $showEditEntry) { entry in
            EditEntryView(entry: entry)
        }
        .sheet(isPresented: $showFoodSheet) {
            VStack(spacing: 20) {
                Text("What did you eat?")
                    .font(.headline)
                    .padding(.top, 24)

                HStack(spacing: 16) {
                    ForEach([StomachState.snack, .fullMeal], id: \.self) { type in
                        Button {
                            appState.addFoodEntry(eventId: eventId, type: type)
                            showFoodSheet = false
                        } label: {
                            VStack(spacing: 8) {
                                Text(type.emoji)
                                    .font(.system(size: 40))
                                Text(type.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Button("Cancel") { showFoodSheet = false }
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .presentationDetents([.height(260)])
        }
        .confirmationDialog("End this night?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Night", role: .destructive) {
                appState.endEvent(eventId)
                appState.pendingSummaryEventId = eventId
                AdManager.shared.showInterstitialIfReady(isPro: appState.isPro)
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
        .sheet(item: $pendingDrink) { warning in
            OverLimitWarningSheet(
                warning: warning,
                onDrinkAnyway: {
                    appState.addDrink(eventId: eventId, drinkTypeId: warning.drinkType.id)
                    pendingDrink = nil
                },
                onAddWater: {
                    appState.addWater(eventId: eventId)
                    pendingDrink = nil
                },
                onAddSnack: {
                    pendingDrink = nil
                    showFoodSheet = true
                },
                onWait: { pendingDrink = nil },
                onCancel: { pendingDrink = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStats) {
            NightStatsSheet(eventId: eventId)
                .environmentObject(appState)
        }
    }

    // MARK: - Drink tap dispatch

    // Intercepts QuickAdd taps. If the projected BAC would cross the night's
    // ceiling (event.targetBAC) or the driving limit (event.bacLimit), present
    // a warning sheet offering water / snack / wait / drink-anyway. Otherwise
    // just log the drink.
    private func handleDrinkTap(_ dt: DrinkType, event: NightEvent, bacLimit: Double) {
        let pBAC = appState.projectedBAC(forEventId: event.id, addingDrinkTypeId: dt.id)
        let nowBAC = appState.currentBAC(for: eventId)
        let beta = BACCalculator.eliminationRate(profile: appState.userProfile)

        var threshold: Double? = nil
        var thresholdLabel: String = ""
        if event.drivingMode, pBAC >= bacLimit, nowBAC < bacLimit {
            threshold = bacLimit
            thresholdLabel = "driving limit"
        } else if let ceiling = event.targetBAC, pBAC >= ceiling, nowBAC < ceiling {
            threshold = ceiling
            thresholdLabel = "your ceiling"
        }

        guard let t = threshold else {
            appState.addDrink(eventId: event.id, drinkTypeId: dt.id)
            return
        }

        // Minutes until current BAC has fallen far enough that adding this
        // drink wouldn't cross `t`. Linear estimate using elimination rate β.
        let over = max(0, pBAC - t)
        let waitMinutes = max(1, Int(ceil((over / max(beta, 0.0001)) * 60)))

        pendingDrink = PendingDrinkWarning(
            drinkType: dt,
            currentBAC: nowBAC,
            projectedBAC: pBAC,
            threshold: t,
            thresholdLabel: thresholdLabel,
            waitMinutes: waitMinutes
        )
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }


}

// MARK: - Pending warning model

struct PendingDrinkWarning: Identifiable {
    let drinkType: DrinkType
    let currentBAC: Double
    let projectedBAC: Double
    let threshold: Double
    let thresholdLabel: String
    let waitMinutes: Int

    var id: String { drinkType.id }
}

// MARK: - DO NOT DRIVE

private struct DriveWarningBanner: View {
    let bac: Double
    let bacLimit: Double
    let beta: Double

    private var hoursRemaining: Double {
        max(0, (bac - bacLimit) / max(beta, 0.005))
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

// MARK: - Target BAC Banner

private struct TargetBACBanner: View {
    let bac: Double
    let target: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("You've reached your ceiling")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                HStack(spacing: 4) {
                    Text(String(format: "%.3f%%", bac))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.accent)
                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)
                    Text(String(format: "ceiling %.2f%%", target))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppColors.accent.opacity(0.1))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
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

    @State private var showLearnView = false

    var body: some View {
        VStack(spacing: 0) {
            // Stage badge row — badge centered, info button trailing
            ZStack {
                Text(stage.name.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.8)
                    .foregroundStyle(stage.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(stage.color.opacity(0.12))
                    .cornerRadius(4)

                HStack {
                    Spacer()
                    Button { showLearnView = true } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                }
            }
            .padding(.top, 20)

            // BAC — massive serif, no orb, no shadow
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(String(format: "%.3f", bac))
                    .font(.system(size: 76, weight: .bold, design: .serif))
                    .foregroundStyle(stage.color)
                Text("%")
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(stage.color.opacity(0.5))
                    .padding(.bottom, 10)
            }
            .padding(.top, 4)

            Text(stage.blurb)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            BACGaugeArc(bac: bac, stage: stage, drivingMode: drivingMode, bacLimit: bacLimit)
                .padding(.horizontal, 20)
                .padding(.top, 10)

            if drivingMode {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(AppColors.danger)
                        .frame(width: 14, height: 1.5)
                    Text(String(format: "limit %.2f%%", bacLimit))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.danger.opacity(0.7))
                }
                .padding(.top, 6)
            }

            if bac > 0 {
                let hours = BACCalculator.hoursToZeroBAC(bac)
                let h = Int(hours)
                let m = Int((hours - Double(h)) * 60)
                Text("~\(h)h \(m)m to sober")
                    .font(.system(size: 11))
                    .tracking(0.3)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 8)
            }

            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .premiumCard(
            radius: 20,
            tint: stage.color,
            tintOpacity: 0.04,
            borderTop: stage.color.opacity(0.3),
            borderBottom: stage.color.opacity(0.05)
        )
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.4), value: stage.name)
        .sheet(isPresented: $showLearnView) {
            NavigationStack {
                LearnView()
                    .navigationTitle("Alcohol & BAC Guide")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showLearnView = false }
                        }
                    }
            }
        }
    }
}

// MARK: - BAC Gauge Arc

private struct BACGaugeArc: View {
    let bac: Double
    let stage: IntoxicationStage
    let drivingMode: Bool
    let bacLimit: Double

    private var fillFraction: Double { IntoxicationStage.barPosition(for: bac) }

    var body: some View {
        ZStack {
            // Stage-colored zone track + limit needle via Canvas (no animation needed)
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height)
                let radius = min(size.width / 2 - 4, size.height - 6)
                let lw: CGFloat = 12

                for s in IntoxicationStage.all {
                    let sf = IntoxicationStage.barPosition(for: s.minBAC)
                    let ef = IntoxicationStage.barPosition(for: s.maxBAC)
                    var p = Path()
                    p.addArc(center: center, radius: radius,
                             startAngle: .degrees(180 + sf * 180),
                             endAngle: .degrees(180 + ef * 180),
                             clockwise: false)
                    ctx.stroke(p, with: .color(s.color.opacity(0.22)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .butt))
                }

                if drivingMode {
                    let lf = IntoxicationStage.barPosition(for: bacLimit)
                    let la = (180.0 + lf * 180.0) * .pi / 180.0
                    let inner = radius - lw / 2 - 2
                    let outer = radius + lw / 2 + 2
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + cos(la) * inner,
                                         y: center.y + sin(la) * inner))
                    tick.addLine(to: CGPoint(x: center.x + cos(la) * outer,
                                            y: center.y + sin(la) * outer))
                    ctx.stroke(tick, with: .color(AppColors.danger),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }

            // Animated fill arc (Shape gives animatableData support)
            GaugeFillArc(fraction: fillFraction)
                .stroke(stage.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fillFraction)
        }
        .frame(height: 100)
    }
}

private struct GaugeFillArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fraction > 0.005 else { return p }
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width / 2 - 4, rect.height - 6)
        p.addArc(center: center, radius: radius,
                 startAngle: .degrees(180),
                 endAngle: .degrees(180 + fraction * 180),
                 clockwise: false)
        return p
    }
}

// MARK: - Current Drink In Progress

private struct CurrentDrinkCard: View {
    let entries: [DrinkEntry]
    let drinkTypes: [DrinkType]
    let now: Date

    @State private var pulse = false

    private var currentEntry: DrinkEntry? { entries.first }
    private var drinkType: DrinkType? {
        guard let e = currentEntry else { return nil }
        return drinkTypes.first { $0.id == e.drinkTypeId }
    }
    private var elapsedMin: Double {
        guard let e = currentEntry else { return 0 }
        return max(0, now.timeIntervalSince(e.timestamp) / 60.0)
    }
    private var totalMin: Double { Double(drinkType?.effectiveDrinkingMinutes ?? 20) }
    private var progress: Double { min(1.0, elapsedMin / totalMin) }

    var body: some View {
        if let dt = drinkType, elapsedMin < totalMin {
            let fillFraction = 1.0 - progress
            let minsLeft = max(1, Int(ceil(totalMin - elapsedMin)))

            HStack(spacing: 14) {
                // Animated glass
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(dt.color.opacity(0.45), lineWidth: 1.5)
                    LiquidFill(fillFraction: fillFraction)
                        .fill(LinearGradient(
                            colors: [dt.color.opacity(pulse ? 0.60 : 0.50),
                                     dt.color.opacity(pulse ? 0.28 : 0.20)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(.easeInOut(duration: 3.0), value: fillFraction)
                }
                .frame(width: 30, height: 50)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dt.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                            Text("sipping now")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        Spacer()
                        HStack(alignment: .lastTextBaseline, spacing: 1) {
                            Text("\(Int(elapsedMin))")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(dt.color)
                            Text(" / \(Int(totalMin))m")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppColors.border)
                                .frame(height: 4)
                            Capsule()
                                .fill(dt.color.opacity(0.85))
                                .frame(width: max(0, geo.size.width * CGFloat(fillFraction)), height: 4)
                                .animation(.easeInOut(duration: 3.0), value: fillFraction)
                        }
                    }
                    .frame(height: 4)

                    Text("~\(minsLeft)m left to absorb")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(14)
            .premiumCard(radius: 14, tint: dt.color, tintOpacity: 0.06)
            .padding(.horizontal)
        }
    }
}

private struct LiquidFill: Shape {
    var fillFraction: Double

    var animatableData: Double {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let h = rect.height * max(0, min(1, fillFraction))
        return Path(roundedRect: CGRect(
            x: rect.minX, y: rect.maxY - h,
            width: rect.width, height: h
        ), cornerRadius: 5)
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
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(color == AppColors.accent ? AppColors.text : color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
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

private struct DrinkImpact {
    let safeDriveLabel: String?   // e.g. "Safe ~1:30 AM" — only when drivingMode
    let hitsTarget: Bool           // true when this drink would push BAC >= targetBAC
}

private struct QuickAddGrid: View {
    @EnvironmentObject var appState: AppState
    let event: NightEvent
    let drinkTypes: [DrinkType]
    let onPick: (DrinkType) -> Void

    let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    // Precomputed once per bacTick — one projectedBAC call per drink type.
    private var impacts: [String: DrinkImpact] {
        _ = appState.bacTick
        let tf = DateFormatter(); tf.timeStyle = .short
        let bacLimit = event.bacLimit ?? appState.userProfile.resolvedBACLimit
        return Dictionary(uniqueKeysWithValues: drinkTypes.map { dt in
            let pBAC = appState.projectedBAC(forEventId: event.id, addingDrinkTypeId: dt.id)
            var safeDrive: String? = nil
            if event.drivingMode {
                let hoursUntilSafe = pBAC > bacLimit
                    ? (pBAC - bacLimit) / BACCalculator.eliminationRate(profile: appState.userProfile)
                    : 0
                if hoursUntilSafe > 0.08 {  // only label if > ~5 min impact
                    let safeDate = Date().addingTimeInterval(hoursUntilSafe * 3600)
                    safeDrive = "Safe ~\(tf.string(from: safeDate))"
                }
            }
            let hitsTarget: Bool
            if let target = event.targetBAC {
                hitsTarget = pBAC >= target
            } else {
                hitsTarget = false
            }
            return (dt.id, DrinkImpact(safeDriveLabel: safeDrive, hitsTarget: hitsTarget))
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("QUICK ADD")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.textTertiary)
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(drinkTypes) { dt in
                    DrinkTile(drinkType: dt, impact: impacts[dt.id]) {
                        onPick(dt)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct DrinkTile: View {
    let drinkType: DrinkType
    let impact: DrinkImpact?
    let onTap: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: drinkType.sfSymbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(drinkType.color.opacity(0.8))

                Spacer()

                Text(drinkType.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)

                // Drive / target impact label — one line, max 11pt
                if let label = impact?.safeDriveLabel {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppColors.danger.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 2)
                } else if impact?.hitsTarget == true {
                    Text("Hits your goal")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppColors.accent)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
            .premiumCard(radius: 14, tint: drinkType.color, tintOpacity: 0.06)
            .scaleEffect(pressed ? 0.91 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded   { _ in pressed = false }
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

private enum TLItem: Identifiable {
    case drink(DrinkEntry)
    case water(WaterEntry)
    case food(FoodEntry)

    var id: String {
        switch self {
        case .drink(let e): return "d\(e.id)"
        case .water(let w): return "w\(w.id)"
        case .food(let e):  return "f\(e.id)"
        }
    }
    var timestamp: Date {
        switch self {
        case .drink(let e): return e.timestamp
        case .water(let w): return w.timestamp
        case .food(let e):  return e.timestamp
        }
    }
    var isDrink: Bool {
        if case .drink = self { return true }; return false
    }
}

private struct TimelineSection: View {
    let entries: [DrinkEntry]
    let waterEntries: [WaterEntry]
    let foodEntries: [FoodEntry]
    let drinkTypes: [DrinkType]
    let onDeleteEntry: (String) -> Void
    let onDeleteWater: (String) -> Void

    private var items: [TLItem] {
        (
            entries.map    { TLItem.drink($0) } +
            waterEntries.map { TLItem.water($0) } +
            foodEntries.map  { TLItem.food($0) }
        ).sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("TIMELINE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.textTertiary)
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)
            }
            .padding(.horizontal)
            .padding(.bottom, 14)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                TLRow(
                    item: item,
                    isFirst: index == 0,
                    isLast: index == items.count - 1,
                    drinkTypes: drinkTypes,
                    onDeleteEntry: onDeleteEntry,
                    onDeleteWater: onDeleteWater,
                    delay: Double(min(index, 6)) * 0.055
                )
            }
        }
    }
}

private struct TLRow: View {
    let item: TLItem
    let isFirst: Bool
    let isLast: Bool
    let drinkTypes: [DrinkType]
    let onDeleteEntry: (String) -> Void
    let onDeleteWater: (String) -> Void
    let delay: Double

    @State private var appeared = false

    private var nodeColor: Color {
        switch item {
        case .drink(let e): return drinkTypes.first { $0.id == e.drinkTypeId }?.color ?? AppColors.accent
        case .water:        return AppColors.water
        case .food:         return AppColors.accent
        }
    }

    private static let tf: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // — spine —
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : AppColors.border.opacity(0.55))
                    .frame(width: 1.5, height: 18)
                ZStack {
                    Circle()
                        .fill(nodeColor.opacity(0.18))
                        .frame(width: item.isDrink ? 18 : 13,
                               height: item.isDrink ? 18 : 13)
                    Circle()
                        .fill(nodeColor)
                        .frame(width: item.isDrink ? 8 : 5,
                               height: item.isDrink ? 8 : 5)
                }
                .shadow(color: nodeColor.opacity(0.7),
                        radius: item.isDrink ? 8 : 5, x: 0, y: 0)
                Rectangle()
                    .fill(isLast ? Color.clear : AppColors.border.opacity(0.55))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 18)

            // — card —
            Group {
                switch item {
                case .drink(let e):
                    let dt = drinkTypes.first { $0.id == e.drinkTypeId }
                    TLDrinkCard(
                        entry: e, drinkType: dt,
                        time: Self.tf.string(from: e.timestamp),
                        onDelete: { onDeleteEntry(e.id) }
                    )
                case .water(let w):
                    TLWaterCard(
                        entry: w,
                        time: Self.tf.string(from: w.timestamp),
                        onDelete: { onDeleteWater(w.id) }
                    )
                case .food(let entry):
                    TLFoodCard(entry: entry)
                }
            }
            .padding(.bottom, isLast ? 4 : 10)
        }
        .padding(.horizontal, 16)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.80).delay(delay)) {
                appeared = true
            }
        }
    }
}

private struct TLDrinkCard: View {
    let entry: DrinkEntry
    let drinkType: DrinkType?
    let time: String
    let onDelete: () -> Void

    private var displayAbv: Double {
        entry.abvOverride ?? drinkType?.defaultAbv ?? 0
    }
    private var displayVol: Double {
        entry.volumeOverrideMl ?? drinkType?.defaultVolumeMl ?? 0
    }

    private var tint: Color { drinkType?.color ?? AppColors.accent }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 8)

            HStack(spacing: 10) {
                Image(systemName: drinkType?.sfSymbol ?? "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if entry.quantity > 1 {
                            Text("×\(entry.quantity)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.15))
                                .cornerRadius(4)
                        }
                        Text(drinkType?.name ?? "Drink")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                    }

                    HStack(spacing: 5) {
                        if displayAbv > 0 {
                            Text(String(format: "%.0f%% ABV", displayAbv))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(AppColors.border.opacity(0.6))
                                .cornerRadius(4)
                        }
                        if displayVol > 0 {
                            Text("\(Int(displayVol)) ml")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        if let c = entry.comment, !c.isEmpty {
                            Text(c)
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Text(time)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tint.opacity(0.15), lineWidth: 1)
                )
        )
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

private struct TLWaterCard: View {
    let entry: WaterEntry
    let time: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [AppColors.water, AppColors.water.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.water)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Water")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("\(Int(entry.volumeMl)) ml")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Text(time)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.water.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.water.opacity(0.12), lineWidth: 1)
                )
        )
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }
}


private struct TLFoodCard: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.type.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(AppColors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


// MARK: - Bottom Bar

private struct BottomBar: View {
    let onAddWater: () -> Void
    let onAddFood: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onAddWater) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 13))
                    Text("Water")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.water)
                .frame(width: 90, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.water.opacity(0.35), lineWidth: 1))
            }

            Button(action: onAddFood) {
                HStack(spacing: 6) {
                    Text("🍟")
                        .font(.system(size: 13))
                    Text("Food")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.accent)
                .frame(width: 90, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.accent.opacity(0.35), lineWidth: 1))
            }

            Button(action: onEnd) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                    Text("End Night")
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(0.2)
                }
                .foregroundStyle(AppColors.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.danger.opacity(0.35), lineWidth: 1))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(AppColors.border), alignment: .top)
    }
}

// MARK: - Over-Limit Warning Sheet

struct OverLimitWarningSheet: View {
    let warning: PendingDrinkWarning
    let onDrinkAnyway: () -> Void
    let onAddWater: () -> Void
    let onAddSnack: () -> Void
    let onWait: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let stage = IntoxicationStage.stage(for: warning.projectedBAC)
        let over  = max(0, warning.projectedBAC - warning.threshold)

        VStack(spacing: 0) {

            // Header
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(stage.color)
                    .padding(.top, 24)

                Text("Heads up")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.text)

                Text("This \(warning.drinkType.name) would push you past \(warning.thresholdLabel).")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            // BAC delta row
            HStack(spacing: 18) {
                bacBlock(label: "Now",
                         value: warning.currentBAC,
                         color: AppColors.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
                bacBlock(label: "After drink",
                         value: warning.projectedBAC,
                         color: stage.color)
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textTertiary)
                bacBlock(label: "Ceiling",
                         value: warning.threshold,
                         color: AppColors.textSecondary)
            }
            .padding(.vertical, 22)

            Text(String(format: "That's %.3f%% over.", over))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(stage.color)
                .padding(.bottom, 16)

            // Actions
            VStack(spacing: 10) {
                actionButton(
                    title: "Wait ~\(warning.waitMinutes) min",
                    subtitle: "Your body burns it off — then this drink is in range",
                    icon: "hourglass",
                    tint: AppColors.accent,
                    onTap: onWait
                )

                actionButton(
                    title: "Add a glass of water",
                    subtitle: "Doesn't lower BAC, but paces the night",
                    icon: "drop.fill",
                    tint: AppColors.water,
                    onTap: onAddWater
                )

                actionButton(
                    title: "Grab a snack",
                    subtitle: "Slows absorption of any drink you have next",
                    icon: "fork.knife",
                    tint: .orange,
                    onTap: onAddSnack
                )

                Button(action: onDrinkAnyway) {
                    Text("Drink anyway")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.danger.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button("Cancel", action: onCancel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }

    private func bacBlock(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%.3f", value))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    private func actionButton(title: String,
                              subtitle: String,
                              icon: String,
                              tint: Color,
                              onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(12)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

