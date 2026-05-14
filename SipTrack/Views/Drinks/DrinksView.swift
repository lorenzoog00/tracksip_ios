import SwiftUI

struct DrinksView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingDrink: DrinkType? = nil
    @State private var showCreate = false
    @State private var deleteConfirm: DrinkType? = nil

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(appState.allDrinkTypes) { dt in
                        DrinkCard(drink: dt) {
                            editingDrink = dt
                        } onDelete: {
                            deleteConfirm = dt
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Drinks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus").foregroundStyle(AppColors.accent)
                }
            }
        }
        .sheet(item: $editingDrink) { dt in
            EditDrinkView(existing: dt)
        }
        .sheet(isPresented: $showCreate) {
            EditDrinkView(existing: nil)
        }
        .confirmationDialog(
            "Delete \(deleteConfirm?.name ?? "drink")?",
            isPresented: Binding(get: { deleteConfirm != nil }, set: { if !$0 { deleteConfirm = nil } }),
            titleVisibility: .visible
        ) {
            Button(deleteConfirm?.isPreset == true ? "Reset to Default" : "Delete", role: .destructive) {
                if let dt = deleteConfirm {
                    appState.deleteDrinkType(dt.id)
                    deleteConfirm = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteConfirm = nil }
        }
    }
}

private struct DrinkCard: View {
    let drink: DrinkType
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: drink.sfSymbol)
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.accent)
                    if !drink.isPreset {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(drink.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                VStack(spacing: 2) {
                    Text("\(Int(drink.defaultVolumeMl))ml · \(String(format: "%.1f", drink.defaultAbv))%")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                    Text("\(Int(drink.caloriesPerServing)) kcal · ~\(drink.effectiveDrinkingMinutes)m")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppColors.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        }
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: {
                Label(drink.isPreset ? "Reset to Default" : "Delete", systemImage: "trash")
            }
        }
    }
}
