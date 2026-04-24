import SwiftUI

struct EditDrinkView: View {
    let existing: DrinkType?
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var volumeStr: String
    @State private var abvStr: String
    @State private var caloriesStr: String
    @State private var icon: String

    private let iconOptions = [
        "mug.fill", "wineglass.fill", "wineglass", "sparkles",
        "flask.fill", "flask", "drop.fill", "leaf.fill",
        "snowflake", "sun.max.fill", "cup.and.saucer.fill", "fork.knife"
    ]

    init(existing: DrinkType?) {
        self.existing = existing
        _name         = State(initialValue: existing?.name ?? "")
        _volumeStr    = State(initialValue: existing.map { "\(Int($0.defaultVolumeMl))" } ?? "355")
        _abvStr       = State(initialValue: existing.map { String(format: "%.1f", $0.defaultAbv) } ?? "5.0")
        _caloriesStr  = State(initialValue: existing.map { "\(Int($0.caloriesPerServing))" } ?? "150")
        _icon         = State(initialValue: existing?.sfSymbol ?? "cup.and.saucer.fill")
    }

    private var isValid: Bool {
        !name.isEmpty &&
        Double(volumeStr) != nil &&
        Double(abvStr) != nil &&
        Double(caloriesStr) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Icon picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                                ForEach(iconOptions, id: \.self) { sym in
                                    Button {
                                        icon = sym
                                    } label: {
                                        Image(systemName: sym)
                                            .font(.system(size: 20))
                                            .foregroundStyle(icon == sym ? .black : AppColors.textSecondary)
                                            .frame(width: 44, height: 44)
                                            .background(icon == sym ? AppColors.accent : AppColors.surface)
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }

                        field(label: "Name", placeholder: "e.g. Rosé Wine", text: $name)
                        numericField(label: "Volume (ml)", placeholder: "355", text: $volumeStr)
                        numericField(label: "ABV (%)", placeholder: "5.0", text: $abvStr)
                        numericField(label: "Calories per serving", placeholder: "150", text: $caloriesStr)

                        Spacer(minLength: 20)

                        Button {
                            save()
                        } label: {
                            Text(existing == nil ? "Add Drink" : "Save Changes")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isValid ? AppColors.accent : AppColors.border)
                                .foregroundStyle(isValid ? Color.black : AppColors.textTertiary)
                                .cornerRadius(14)
                        }
                        .disabled(!isValid)
                    }
                    .padding()
                }
            }
            .navigationTitle(existing == nil ? "New Drink" : "Edit Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField(placeholder, text: text)
                .padding(12)
                .background(AppColors.surface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                .foregroundStyle(AppColors.text)
        }
    }

    private func numericField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .padding(12)
                .background(AppColors.surface)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                .foregroundStyle(AppColors.text)
        }
    }

    private func save() {
        let id   = existing?.id ?? generateId()
        let type = DrinkType(
            id: id,
            name: name,
            defaultVolumeMl: Double(volumeStr) ?? 355,
            defaultAbv: Double(abvStr) ?? 5.0,
            caloriesPerServing: Double(caloriesStr) ?? 150,
            isPreset: existing?.isPreset ?? false,
            icon: icon
        )
        appState.saveDrinkType(type)
        dismiss()
    }
}
