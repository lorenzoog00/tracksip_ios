import SwiftUI

struct EditDrinkView: View {
    let existing: DrinkType?
    private let highlightsCalories: Bool
    private let onSave: (DrinkType) -> Void
    private let calorieFieldID = "calories-per-serving"
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var volumeStr: String
    @State private var abvStr: String
    @State private var caloriesStr: String
    @State private var durationStr: String
    @State private var icon: String
    @State private var colorHex: String?

    @State private var lookupQuery = ""
    @State private var lookupState = LookupState.idle
    @State private var lookupNote: String?
    @State private var lookupsLeft: Int?

    private enum LookupState: Equatable {
        case idle, loading
        case failed(String)
    }

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

    init(
        existing: DrinkType?, highlightsCalories: Bool = false,
        suggestedName: String = "", onSave: @escaping (DrinkType) -> Void = { _ in }
    ) {
        self.existing = existing
        self.highlightsCalories = highlightsCalories
        self.onSave = onSave
        _name         = State(initialValue: existing?.name ?? suggestedName)
        _volumeStr    = State(initialValue: existing.map { "\(Int($0.defaultVolumeMl))" } ?? "355")
        _abvStr       = State(initialValue: existing.map { String(format: "%.1f", $0.defaultAbv) } ?? "5.0")
        _caloriesStr  = State(initialValue: existing.map { "\(Int($0.caloriesPerServing))" } ?? "150")
        _durationStr  = State(initialValue: "\(existing?.effectiveDrinkingMinutes ?? 20)")
        _icon         = State(initialValue: existing?.sfSymbol ?? "cup.and.saucer.fill")
        _colorHex     = State(initialValue: existing?.colorHex)
        // Arriving from the picker's search, the name is already typed: it is
        // the one thing the user should not have to write twice.
        _lookupQuery  = State(initialValue: existing == nil ? suggestedName : "")
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
            editorContent
        }
    }

    private var editorContent: some View {
        ScrollViewReader { scroll in
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if existing == nil { autofillCard }
                        field(label: "Name", placeholder: "e.g. Rosé Wine", text: $name)
                        numericField(
                            label: "Avg. time to finish (min)",
                            placeholder: "20",
                            text: $durationStr,
                            footnote: "How long you typically take to drink one. Used to spread your BAC rise realistically."
                        )

                        // Icon picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Icon")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                                ForEach(iconOptions, id: \.self) { sym in
                                    Button {
                                        icon = sym
                                    } label: {
                                        Image(systemName: sym)
                                            .font(.system(size: 22))
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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                if colorHex != nil {
                                    Button("Clear") { colorHex = nil }
                                        .font(.system(size: 14))
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
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        numericField(label: "Volume (ml)", placeholder: "355", text: $volumeStr)
                        numericField(label: "ABV (%)", placeholder: "5.0", text: $abvStr)
                        numericField(
                            label: "Calories per serving", placeholder: "150", text: $caloriesStr,
                            footnote: highlightsCalories ? "Enter the calories for the serving size above, then save." : nil
                        )
                        .guideHighlight(highlightsCalories)
                        .id(calorieFieldID)

                        Spacer(minLength: 20)

                        Button {
                            save()
                        } label: {
                            Text(existing == nil ? "Add Drink" : "Save Changes")
                                .font(.system(size: 18, weight: .semibold))
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
                .task {
                    guard highlightsCalories else { return }
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    scroll.scrollTo(calorieFieldID, anchor: .center)
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

    // MARK: - Autofill

    private var canAutofill: Bool {
        lookupState != .loading &&
        (try? DrinkLookup.normalizedQuery(lookupQuery)) != nil
    }

    private var autofillCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Don't know the numbers?")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            HStack(spacing: 8) {
                // Taken from the suggestions so the placeholder is covered by
                // the same test: a preset's name here would teach the user
                // that the field only repeats what they could have tapped.
                TextField("e.g. \(DrinkLookup.examples.first ?? "")", text: $lookupQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { autofill() }
                    .padding(12)
                    .background(AppColors.surface)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                    .foregroundStyle(AppColors.text)
                Button(action: autofill) {
                    Group {
                        if lookupState == .loading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .frame(width: 52, height: 46)
                    .background(canAutofill ? AppColors.accent : AppColors.border)
                    .foregroundStyle(canAutofill ? Color.black : AppColors.textTertiary)
                    .cornerRadius(10)
                }
                .disabled(!canAutofill)
                .accessibilityLabel("Fill in the drink's details")
            }
            // Only while the field is empty: once there is something to look
            // up, the suggestions are in the way of the button.
            if lookupQuery.isEmpty && lookupState != .loading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DrinkLookup.examples, id: \.self) { example in
                            Button {
                                lookupQuery = example
                                lookupState = .idle
                            } label: {
                                Text(example)
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(AppColors.surface)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppColors.border, lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            if case .failed(let message) = lookupState {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accentWarm)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let lookupNote {
                Text(lookupNote)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Name any drink — even one that isn't in the list. We'll estimate the pour, ABV and calories for you to check.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(AppColors.surface.opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
    }

    private func autofill() {
        guard canAutofill else { return }
        // A drink the user already has costs nothing to copy, and the monthly
        // allowance is small enough that spending one on a repeat would be the
        // worst use of it.
        if let match = DrinkLookup.localMatch(for: lookupQuery, in: appState.allDrinkTypes) {
            let quantity = DrinkLookup.leadingCount(in: lookupQuery)
            apply(DrinkLookup.result(from: match, quantity: quantity),
                  note: "Copied from your “\(match.name)”. No lookup used.")
            return
        }
        lookupState = .loading
        Task { @MainActor in
            do {
                let (result, remaining) = try await FirebaseManager.shared.lookupDrink(query: lookupQuery)
                lookupsLeft = remaining
                apply(result, note: nil)
            } catch {
                lookupState = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ result: DrinkLookupResult, note: String?) {
        name = result.name
        volumeStr = "\(Int(result.volumeMl.rounded()))"
        abvStr = String(format: "%.1f", result.abv)
        caloriesStr = "\(Int(result.calories.rounded()))"
        durationStr = "\(result.minutes)"
        icon = DrinkLookup.sfSymbol(for: result.category)
        lookupState = .idle
        var lines = [note ?? "Estimated — check the numbers below before saving."]
        if result.quantity > 1 {
            // The form creates a drink, it does not log one, so saying this is
            // the honest thing to do rather than quietly logging servings the
            // user never tapped.
            lines.append("You said \(result.quantity) servings — tap the drink that many times to log them.")
        }
        if let left = lookupsLeft, note == nil {
            lines.append(left == 1 ? "1 autofill left this month." : "\(left) autofills left this month.")
        }
        lookupNote = lines.joined(separator: " ")
        Haptics.shared.play(.success)
    }

    private func field(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 16, weight: .medium))
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
                .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 14))
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
        onSave(type)
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
