import SwiftUI

// MARK: - Filter

private enum DrinkFilter: String, CaseIterable {
    case all, favorites, beer, wine, spirits, cocktail

    var label: String {
        switch self {
        case .all:       return "All"
        case .favorites: return "♥ Favorites"
        case .beer:      return "Beer"
        case .wine:      return "Wine"
        case .spirits:   return "Spirits"
        case .cocktail:  return "Cocktail"
        }
    }

    func matches(_ dt: DrinkType, isFav: Bool) -> Bool {
        switch self {
        case .all:       return true
        case .favorites: return isFav
        case .beer:      return dt.drinkCategory == "beer"
        case .wine:      return dt.drinkCategory == "wine"
        case .spirits:   return dt.drinkCategory == "spirits" || dt.drinkCategory == "agave"
        case .cocktail:  return dt.drinkCategory == "cocktails"
        }
    }
}

// MARK: - Main view

struct DrinksView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingDrink: DrinkType? = nil
    @State private var showCreate = false
    @State private var deleteConfirm: DrinkType? = nil
    @State private var filter: DrinkFilter = .all

    private var filtered: [DrinkType] {
        appState.allDrinkTypes.filter { filter.matches($0, isFav: appState.isFavorite($0.id)) }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                filterPills
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { dt in
                            DrinkRow(
                                drink: dt,
                                isFavorite: appState.isFavorite(dt.id),
                                onFavorite: { appState.toggleFavoriteDrink(id: dt.id) },
                                onEdit: { editingDrink = dt },
                                onDelete: { deleteConfirm = dt }
                            )
                        }
                        createButton
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Drinks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDrink) { EditDrinkView(existing: $0) }
        .sheet(isPresented: $showCreate) { EditDrinkView(existing: nil) }
        .confirmationDialog(
            "Delete \(deleteConfirm?.name ?? "drink")?",
            isPresented: Binding(get: { deleteConfirm != nil }, set: { if !$0 { deleteConfirm = nil } }),
            titleVisibility: .visible
        ) {
            Button(deleteConfirm?.isPreset == true ? "Reset to Default" : "Delete", role: .destructive) {
                if let dt = deleteConfirm { appState.deleteDrinkType(dt.id); deleteConfirm = nil }
            }
            Button("Cancel", role: .cancel) { deleteConfirm = nil }
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DrinkFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { filter = f }
                    } label: {
                        Text(f.label)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(filter == f ? AppColors.accent : AppColors.surface)
                            .foregroundStyle(filter == f ? Color.black : AppColors.textSecondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(filter == f ? AppColors.accent : AppColors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(AppColors.background)
    }

    private var createButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                Text("Create new drink")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.accent.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Row

private struct DrinkRow: View {
    let drink: DrinkType
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(drink.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: drink.sfSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(drink.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(drink.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(String(format: "%.1f%% · %dml · %d cal", drink.defaultAbv, Int(drink.defaultVolumeMl), Int(drink.caloriesPerServing)))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isFavorite ? Color(hex: "#FF6B6B") : AppColors.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { onFavorite() } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label(drink.isPreset ? "Reset to Default" : "Delete", systemImage: "trash")
            }
        }
    }
}
