import SwiftUI

struct EditEntryView: View {
    let entry: DrinkEntry
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var quantity: Int
    @State private var volumeStr: String
    @State private var abvStr: String
    @State private var comment: String

    private var drinkType: DrinkType? {
        appState.allDrinkTypes.first { $0.id == entry.drinkTypeId }
    }

    init(entry: DrinkEntry) {
        self.entry = entry
        _quantity   = State(initialValue: entry.quantity)
        _volumeStr  = State(initialValue: entry.volumeOverrideMl.map { "\(Int($0))" } ?? "")
        _abvStr     = State(initialValue: entry.abvOverride.map { String(format: "%.1f", $0) } ?? "")
        _comment    = State(initialValue: entry.comment ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Drink name header
                    if let dt = drinkType {
                        HStack(spacing: 10) {
                            Image(systemName: dt.sfSymbol)
                                .font(.system(size: 20))
                                .foregroundStyle(AppColors.accent)
                            Text(dt.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                        }
                        .padding(.top)
                    }

                    // Quantity stepper
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quantity")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        HStack(spacing: 20) {
                            Button {
                                if quantity > 1 { quantity -= 1 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(quantity > 1 ? AppColors.accent : AppColors.border)
                            }
                            Text("\(quantity)")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(AppColors.text)
                                .frame(minWidth: 40)
                            Button {
                                quantity += 1
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AppColors.accent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(12)

                    // Overrides
                    VStack(spacing: 12) {
                        optionalField(
                            label: "Volume override (ml)",
                            placeholder: drinkType.map { "\(Int($0.defaultVolumeMl))" } ?? "355",
                            text: $volumeStr
                        )
                        optionalField(
                            label: "ABV override (%)",
                            placeholder: drinkType.map { String(format: "%.1f", $0.defaultAbv) } ?? "5.0",
                            text: $abvStr
                        )
                        optionalField(label: "Comment (optional)", placeholder: "e.g. Strong pour", text: $comment)
                    }

                    Spacer()

                    Button { save() } label: {
                        Text("Save Changes")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.accent)
                            .foregroundStyle(.black)
                            .cornerRadius(14)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private func optionalField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(label.contains("Comment") ? .default : .decimalPad)
                .padding(12)
                .background(AppColors.surface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                .foregroundStyle(AppColors.text)
        }
    }

    private func save() {
        var updated = entry
        updated.quantity         = quantity
        updated.volumeOverrideMl = Double(volumeStr)
        updated.abvOverride      = Double(abvStr)
        updated.comment          = comment.isEmpty ? nil : comment
        appState.updateEntry(updated)
        dismiss()
    }
}
