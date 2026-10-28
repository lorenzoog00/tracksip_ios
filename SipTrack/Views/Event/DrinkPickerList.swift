import SwiftUI

// MARK: - Filter enum

enum PickerFilter: Hashable, CaseIterable {
    case favorites, all, beer, wine, spirits, cocktail

    var label: String {
        switch self {
        case .favorites: return "♥ Favorites"
        case .all:       return "All"
        case .beer:      return "Beer"
        case .wine:      return "Wine"
        case .spirits:   return "Spirits"
        case .cocktail:  return "Cocktail"
        }
    }

    func matches(_ dt: DrinkType, isFav: Bool) -> Bool {
        switch self {
        case .favorites: return isFav
        case .all:       return true
        case .beer:      return dt.drinkCategory == "beer"
        case .wine:      return dt.drinkCategory == "wine"
        case .spirits:   return dt.drinkCategory == "spirits" || dt.drinkCategory == "agave"
        case .cocktail:  return dt.drinkCategory == "cocktails"
        }
    }
}

// MARK: - Main picker

struct DrinkPickerList: View {
    @EnvironmentObject var appState: AppState
    let event: NightEvent
    let drinkTypes: [DrinkType]
    let onPick: (DrinkType) -> Void
    let onPickSized: (DrinkType, ServingSizeOption) -> Void

    @State private var filter: PickerFilter = .all
    @State private var searchText = ""

    private var hasFavorites: Bool {
        drinkTypes.contains { appState.isFavorite($0.id) }
    }

    private var latestTimestampByDrinkId: [String: Date] {
        var result: [String: Date] = [:]
        for entry in appState.entries where entry.eventId == event.id {
            if result[entry.drinkTypeId] == nil || entry.timestamp > result[entry.drinkTypeId]! {
                result[entry.drinkTypeId] = entry.timestamp
            }
        }
        return result
    }

    // Drinks added during this session, most recent first, capped at 5
    private var recentDrinkTypes: [DrinkType] {
        let sessionEntries = appState.entries
            .filter { $0.eventId == event.id }
            .sorted { $0.timestamp > $1.timestamp }
        var seen = Set<String>()
        var result: [DrinkType] = []
        for entry in sessionEntries {
            guard !seen.contains(entry.drinkTypeId) else { continue }
            seen.insert(entry.drinkTypeId)
            if let dt = drinkTypes.first(where: { $0.id == entry.drinkTypeId }) {
                result.append(dt)
                if result.count == 5 { break }
            }
        }
        return result
    }

    private var filteredDrinks: [DrinkType] {
        let base = drinkTypes.filter { filter.matches($0, isFav: appState.isFavorite($0.id)) }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // Pre-computed to avoid let-in-ViewBuilder type-check issues
    private var allMinusRecent: [DrinkType] {
        let recentIds = Set(recentDrinkTypes.map(\.id))
        return filteredDrinks.filter { !recentIds.contains($0.id) }
    }

    private var showBothSections: Bool {
        filter == .all && searchText.isEmpty && !recentDrinkTypes.isEmpty
    }

    private func pillBackground(_ f: PickerFilter) -> Color {
        guard filter == f else { return AppColors.surface }
        return f == .favorites ? Color(hex: "#FF6B6B") : AppColors.accent
    }

    private func pillBorderColor(_ f: PickerFilter) -> Color {
        guard filter == f else { return AppColors.border }
        return f == .favorites ? Color(hex: "#FF6B6B") : AppColors.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
                TextField("Search drinks…", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.text)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
            .padding(.horizontal)

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PickerFilter.allCases, id: \.self) { f in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                filter = f
                                searchText = ""
                            }
                        } label: {
                            Text(f.label)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(pillBackground(f))
                                .foregroundStyle(filter == f ? AppColors.background : AppColors.textSecondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(pillBorderColor(f), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Content
            VStack(spacing: 5) {
                if showBothSections {
                    pickerSection(label: "RECENTLY ADDED", color: AppColors.accent, drinks: recentDrinkTypes, showTimestamp: true)
                    if !allMinusRecent.isEmpty {
                        pickerSection(label: "ALL DRINKS", color: AppColors.textTertiary, drinks: allMinusRecent, showTimestamp: false)
                    }
                } else if filteredDrinks.isEmpty {
                    emptyState
                } else {
                    pickerSection(
                        label: filter == .favorites ? "YOUR FAVORITES" : nil,
                        color: filter == .favorites ? Color(hex: "#FF6B6B") : AppColors.textTertiary,
                        drinks: filteredDrinks,
                        showTimestamp: false
                    )
                }
            }
            .padding(.horizontal)
            .animation(.default, value: filter)
            .animation(.default, value: searchText)
        }
        .onAppear {
            filter = hasFavorites ? .favorites : .all
            // Once for the whole grid: every tile plays through the shared engine,
            // and prepare() re-reads the profile from disk, so it must not run per
            // tile.
            Haptics.shared.prepare()
        }
    }

    // MARK: Sub-views

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Text("ADD A DRINK")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.textTertiary)
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        Text(filter == .favorites
             ? "No favorites yet — heart drinks in the Drinks tab."
             : "No drinks match your search.")
            .font(.system(size: 13))
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    @ViewBuilder
    private func pickerSection(label: String?, color: Color, drinks: [DrinkType], showTimestamp: Bool) -> some View {
        if let label {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(color)
                .padding(.horizontal, 4)
        }
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(drinks) { dt in
                DrinkTile(
                    drinkType: dt,
                    recentTimestamp: showTimestamp ? latestTimestampByDrinkId[dt.id] : nil,
                    onPick: { onPick(dt) },
                    onPickSized: { onPickSized(dt, $0) }
                )
            }
        }
    }
}

// MARK: - Grid Tile

private struct DrinkTile: View {
    let drinkType: DrinkType
    let recentTimestamp: Date?
    let onPick: () -> Void
    let onPickSized: (ServingSizeOption) -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var isRecent: Bool { recentTimestamp != nil }

    var body: some View {
        Button {
            // No haptic here. The confirmation tap is played by AppState.addDrink,
            // which every add goes through, so it follows a drink that was actually
            // logged: a press cancelled by a scroll, or a tap that only raises the
            // limit warning, adds nothing and so gets no confirmation tap. Not
            // silent, in the warning case — ActiveEventView plays `.warning` when
            // it raises the sheet, and the confirmation tap comes later if and when
            // the user confirms the add.
            onPick()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(drinkType.color.opacity(isRecent ? 0.22 : 0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: drinkType.sfSymbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(drinkType.color)
                }

                Text(drinkType.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                if let ts = recentTimestamp {
                    Text(DrinkTile.timeFormatter.string(from: ts))
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.accent)
                } else {
                    Text(String(format: "%.1f%%", drinkType.defaultAbv))
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 115)
            .background(isRecent ? Color(hex: "#141820") : AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isRecent ? AppColors.accent.opacity(0.3) : AppColors.border, lineWidth: 1)
            )
        }
        // The press animation comes from the button style, not a gesture. A
        // DragGesture(minimumDistance: 0) here fired on touch-down and fought
        // the grid's scroll, so the list would not move while a finger rested
        // on a tile. A ButtonStyle's isPressed cancels itself when a scroll
        // starts instead of competing with it.
        .buttonStyle(PressableTile())
        .contextMenu {
            Text("Pour size")
            ForEach(drinkType.servingSizeOptions) { opt in
                Button {
                    onPickSized(opt)
                } label: {
                    Label("\(opt.label) · \(Int(opt.volumeMl)) mL", systemImage: "drop.fill")
                }
            }
        }
    }
}

/// Press feedback that does not block scrolling: the scale and the pour buzz
/// both follow `isPressed`. It is driven by the button itself, so SwiftUI drops
/// it the moment the grid starts to scroll.
private struct PressableTile: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(
                .spring(response: 0.2, dampingFraction: 0.65),
                value: configuration.isPressed
            )
            .modifier(PourHaptic(isPressed: configuration.isPressed))
    }
}

/// The continuous "pour" buzz for a held tile. It starts once the press has
/// lasted `holdDelay`, so a tap never begins it, then swells from
/// `startIntensity` to `peakIntensity`. It ends when the press ends, or
/// `peakHold` after the swell tops out, whichever comes first. It never plays the
/// closing tap: `isPressed` also goes false when the grid takes the touch to
/// scroll, and no drink is added then, so that tap belongs to `AppState.addDrink`.
///
/// A `ButtonStyle` cannot hold state, so the ramp lives here: a `ViewModifier`
/// gets its own storage, and the ramp is a `.task(id:)` so that SwiftUI owns its
/// lifetime rather than a `Task` handle kept by hand.
private struct PourHaptic: ViewModifier {
    let isPressed: Bool

    /// True from `beginContinuous` until the matching `endContinuous`, and the
    /// only gate on `endBuzz`. A buzz can be ended from three places (the release,
    /// the tile disappearing, the time bound below) and this makes the first one to
    /// arrive the only one that acts. It is not a corner case that the tile
    /// disappears: a tap that lands can move the tile from "ALL DRINKS" to
    /// "RECENTLY ADDED", which tears it down in the same update as the release.
    @State private var isBuzzing = false

    // How long a finger must rest before the buzz starts. Shorter than this is a
    // tap, and a tap should feel like a tap rather than a hum and then a tap.
    private static let holdDelay: Duration = .milliseconds(120)

    private static let startIntensity: Float = 0.25
    private static let peakIntensity: Float = 0.8
    // 15 steps of 40 ms is the 0.6 s swell.
    private static let rampSteps = 15
    private static let rampStep: Duration = .milliseconds(40)

    // The buzz bounds itself rather than trusting `isPressed` to go false. If the
    // pressed state were ever left stuck (say, by the "Pour size" menu taking the
    // touch), the buzz would otherwise run to the engine's 20 s cap. This caps it
    // at about a second: the 0.6 s swell plus this hold.
    private static let peakHold: Duration = .milliseconds(400)

    func body(content: Content) -> some View {
        content
            .onChange(of: isPressed) { _, pressed in
                if !pressed { endBuzz() }
            }
            // The whole pour. The task is keyed to `isPressed`, so SwiftUI cancels
            // it the instant the press ends, and also if the tile disappears: a
            // press that ends inside `holdDelay` never reaches `beginBuzz`. A new
            // press starts a fresh task from the bottom, and the old one is already
            // cancelled by then, so ramps never overlap. The release itself is just
            // a task that returns at once.
            .task(id: isPressed) { @MainActor in
                guard isPressed else { return }
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled else { return }
                beginBuzz()
                for step in 1...Self.rampSteps {
                    try? await Task.sleep(for: Self.rampStep)
                    // Cancelled while asleep, or in the gap before this line ran:
                    // the pour is over, so it must not touch the player again.
                    guard !Task.isCancelled else { return }
                    let fraction = Float(step) / Float(Self.rampSteps)
                    Haptics.shared.updateContinuous(
                        intensity: Self.startIntensity + (Self.peakIntensity - Self.startIntensity) * fraction
                    )
                }
                try? await Task.sleep(for: Self.peakHold)
                guard !Task.isCancelled else { return }
                endBuzz()
            }
            .onDisappear { endBuzz() }
    }

    private func beginBuzz() {
        isBuzzing = true
        Haptics.shared.beginContinuous(initialIntensity: Self.startIntensity)
    }

    // Idempotent. The flag is cleared before the engine is told, so a release that
    // arrives after the time bound has already ended the buzz finds it clear and
    // does nothing: one `endContinuous` per `beginContinuous`, never two.
    private func endBuzz() {
        guard isBuzzing else { return }
        isBuzzing = false
        Haptics.shared.endContinuous()
    }
}
