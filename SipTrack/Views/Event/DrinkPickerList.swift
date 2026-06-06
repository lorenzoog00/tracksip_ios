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
                                .background(
                                    filter == f
                                        ? (f == .favorites ? Color(hex: "#FF6B6B") : AppColors.accent)
                                        : AppColors.surface
                                )
                                .foregroundStyle(
                                    filter == f ? AppColors.background : AppColors.textSecondary
                                )
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    filter == f
                                        ? (f == .favorites ? Color(hex: "#FF6B6B") : AppColors.accent)
                                        : AppColors.border,
                                    lineWidth: 1
                                ))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Content
            VStack(spacing: 5) {
                if filter == .all && searchText.isEmpty && !recentDrinkTypes.isEmpty {
                    pickerSection(label: "RECENTLY ADDED", color: AppColors.accent, drinks: recentDrinkTypes, showTimestamp: true)
                    pickerSection(label: "ALL DRINKS", color: AppColors.textTertiary, drinks: filteredDrinks, showTimestamp: false)
                } else if filteredDrinks.isEmpty {
                    emptyState
                } else {
                    let sectionLabel: String? = filter == .favorites ? "YOUR FAVORITES" : nil
                    let sectionColor: Color = filter == .favorites ? Color(hex: "#FF6B6B") : AppColors.textTertiary
                    pickerSection(label: sectionLabel, color: sectionColor, drinks: filteredDrinks, showTimestamp: false)
                }
            }
            .padding(.horizontal)
            .animation(.default, value: filter)
            .animation(.default, value: searchText)
        }
        .onAppear {
            filter = hasFavorites ? .favorites : .all
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

    @ViewBuilder
    private func pickerSection(label: String?, color: Color, drinks: [DrinkType], showTimestamp: Bool) -> some View {
        if let label {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(color)
                .padding(.horizontal, 4)
        }
        ForEach(drinks) { dt in
            PickerRow(
                drinkType: dt,
                recentTimestamp: showTimestamp ? latestTimestampByDrinkId[dt.id] : nil,
                onPick: { onPick(dt) }
            )
        }
    }
}

// MARK: - Row

private struct PickerRow: View {
    let drinkType: DrinkType
    let recentTimestamp: Date?
    let onPick: () -> Void

    @State private var pressed = false
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var metaText: String {
        if let ts = recentTimestamp {
            return "added \(PickerRow.timeFormatter.string(from: ts))"
        }
        return String(format: "%.1f%% · %dml · %d cal",
                      drinkType.defaultAbv,
                      Int(drinkType.defaultVolumeMl),
                      Int(drinkType.caloriesPerServing))
    }

    var body: some View {
        Button {
            haptic.impactOccurred()
            onPick()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(drinkType.color.opacity(recentTimestamp != nil ? 0.2 : 0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: drinkType.sfSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(drinkType.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(drinkType.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                    Text(metaText)
                        .font(.system(size: 9))
                        .foregroundStyle(recentTimestamp != nil ? AppColors.accent : AppColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.border)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                recentTimestamp != nil ? Color(hex: "#141820") : AppColors.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(recentTimestamp != nil ? AppColors.accent.opacity(0.2) : AppColors.border, lineWidth: 1)
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    pressed = true
                    haptic.prepare()
                }
                .onEnded   { _ in pressed = false }
        )
    }
}
