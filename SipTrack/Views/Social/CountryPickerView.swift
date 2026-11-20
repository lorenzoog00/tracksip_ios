import SwiftUI

/// Every country for the phone field: flag, name and dial code, searchable by
/// name ("mex", "México") or by dial code ("52", "+52").
struct CountryPickerView: View {
    /// The region currently chosen, marked with a check.
    let selected: String
    let onPick: (PhoneCountry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [PhoneCountry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return PhoneNumbers.countries }
        // Only digits (and a "+") means a dial code: match its leading digits.
        let isDialCode = trimmed.allSatisfy { character in
            (character.isASCII && character.isWholeNumber) || character == "+" || character == " "
        }
        if isDialCode {
            let digits = trimmed.filter { character in character.isASCII && character.isWholeNumber }
            guard !digits.isEmpty else { return PhoneNumbers.countries }
            return PhoneNumbers.countries.filter { country in String(country.dialCode).hasPrefix(digits) }
        }
        return PhoneNumbers.countries.filter { country in country.name.localizedStandardContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List(results) { country in
                Button {
                    onPick(country)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag)
                            .font(.system(size: 24))
                        Text(country.name)
                            .foregroundStyle(AppColors.text)
                        Spacer()
                        Text(verbatim: "+\(country.dialCode)")
                            .foregroundStyle(AppColors.textSecondary)
                        if country.region == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(AppColors.surface)
                .accessibilityAddTraits(country.region == selected ? .isSelected : [])
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Country or code")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
