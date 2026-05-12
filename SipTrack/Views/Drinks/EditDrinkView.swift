import SwiftUI

struct EditDrinkView: View {
    let existing: DrinkType?
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var volumeStr: String
    @State private var abvStr: String
    @State private var caloriesStr: String
    @State private var durationStr: String
    @State private var icon: String
    @State private var colorHex: String?

    private let iconOptions = [
        "mug.fill", "wineglass.fill", "wineglass", "sparkles",
        "flask.fill", "flask", "drop.fill", "leaf.fill",
        "snowflake", "sun.max.fill", "cup.and.saucer.fill", "fork.knife"
    ]

    private let colorPalette: [(hex: String, label: String)] = [
        ("#F0A830", "Amber"),   ("#C0392B", "Red"),    ("#F1C40F", "Yellow"),
        ("#2ED573", "Lime"),    ("#40AAFF", "Blue"),   ("#9B59B6", "Violet"),
        ("#FF6348", "Orange"),  ("#FF6B81", "Pink"),   ("#ECF0F1", "Silver"),
        ("#1ABC9C", "Teal"),    ("#E67E22", "Copper"), ("#8E44AD", "Purple"),
    ]

    init(existing: DrinkType?) {
        self.existing = existing
        _name         = State(initialValue: existing?.name ?? "")
        _volumeStr    = State(initialValue: existing.map { "\(Int($0.defaultVolumeMl))" } ?? "355")
        _abvStr       = State(initialValue: existing.map { String(format: "%.1f", $0.defaultAbv) } ?? "5.0")
        _caloriesStr  = State(initialValue: existing.map { "\(Int($0.caloriesPerServing))" } ?? "150")
        _durationStr  = State(initialValue: "\(existing?.effectiveDrinkingMinutes ?? 20)")
        _icon         = State(initialValue: existing?.sfSymbol ?? "cup.and.saucer.fill")
        _colorHex     = State(initialValue: existing?.colorHex)
    }

    private var isValid: Bool {
        !name.isEmpty &&
        Double(volumeStr) != nil &&
        Double(abvStr) != nil &&
        Double(caloriesStr) != nil &&
        (Int(durationStr) ?? 0) > 0
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

                        // Color palette
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("Color")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                if colorHex != nil {
                                    Button("Clear") { colorHex = nil }
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                                ForEach(colorPalette, id: \.hex) { swatch in
                                    Button {
                                        colorHex = colorHex == swatch.hex ? nil : swatch.hex
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: swatch.hex))
                                                .frame(width: 38, height: 38)
                                            if colorHex == swatch.hex {
                                                Circle()
                                                    .strokeBorder(.white.opacity(0.9), lineWidth: 2.5)
                                                    .frame(width: 38, height: 38)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        field(label: "Name", placeholder: "e.g. Rosé Wine", text: $name)
                        numericField(
                            label: "Avg. time to finish (min)",
                            placeholder: "20",
                            text: $durationStr,
                            footnote: "How long you typically take to drink one. Used to spread your BAC rise realistically."
                        )
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

    private func numericField(label: String, placeholder: String, text: Binding<String>, footnote: String? = nil) -> some View {
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
            if let note = footnote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            icon: internalIcon(from: icon),
            colorHex: colorHex,
            defaultDrinkingDurationMinutes: Int(durationStr).flatMap { $0 > 0 ? $0 : nil }
        )
        appState.saveDrinkType(type)
        dismiss()
    }

    private func internalIcon(from sfSymbol: String) -> String {
        switch sfSymbol {
        case "mug.fill":          return "beer-outline"
        case "wineglass.fill":    return "wine"
        case "wineglass":         return "wine-sharp"
        case "sparkles":          return "sparkles"
        case "flask.fill":        return "flask-outline"
        case "flask":             return "flask"
        case "drop.fill":         return "water"
        case "leaf.fill":         return "leaf"
        case "snowflake":         return "snow"
        case "sun.max.fill":      return "sunny"
        case "fork.knife":        return "restaurant"
        case "cup.and.saucer.fill": return "cup"
        default:                  return "cup"
        }
    }
}
