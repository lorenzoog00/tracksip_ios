import SwiftUI

// Shown the first time we detect a country via CoreLocation that differs
// from the user's stored country (or when they have none set yet). Two
// modes: matched (we have BAC data for this country) and unknownCountry
// (we don't — surfaced as a softer info-only message).
struct CountryDetectedSheet: View {
    let result: CountryDetectionResult
    let currentCountry: LegalBACLimit?
    let driverType: DriverType
    let onApply: (LegalBACLimit) -> Void
    let onKeepMine: () -> Void
    let onDontAskAgain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            switch result {
            case .matched(let country):
                matchedBody(country: country)
            case .unknownCountry(let code, let name):
                unknownBody(code: code, name: name)
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.background.ignoresSafeArea())
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .padding(.top, 24)
            Text("We checked your location")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.text)
            Text("So we can apply the right drink-drive limit for where you are.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Matched country (we have BAC data)

    @ViewBuilder private func matchedBody(country: LegalBACLimit) -> some View {
        VStack(spacing: 14) {

            // Country card
            HStack(spacing: 14) {
                Text(country.flagEmoji)
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 4) {
                    Text(country.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    HStack(spacing: 6) {
                        Image(systemName: driverType.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                        Text(driverType.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    if let note = country.note {
                        Text(note)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(AppColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Limits — three tiers in one card so the user sees the full picture
            VStack(spacing: 0) {
                limitRow(label: "General",    icon: "car.fill",
                         value: country.general,    highlight: driverType == .general)
                Divider().background(AppColors.border)
                limitRow(label: "Novice / Learner", icon: "graduationcap.fill",
                         value: country.novice,     highlight: driverType == .novice)
                Divider().background(AppColors.border)
                limitRow(label: "Commercial", icon: "truck.box.fill",
                         value: country.commercial, highlight: driverType == .commercial)
            }
            .background(AppColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))

            // Source / disclaimer
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("BAC % limits per WHO and national legislation.")
                    .font(.system(size: 10))
                Spacer()
            }
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, 4)

            // Actions
            actions(applyCountry: country)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Unknown country (no BAC entry)

    @ViewBuilder private func unknownBody(code: String, name: String) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Text(flagEmoji(for: code))
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("No drink-drive data on file")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.danger.opacity(0.85))
                }
                Spacer()
            }
            .padding(14)
            .background(AppColors.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.danger)
                    .padding(.top, 1)
                Text("We don't have the legal BAC limit for \(name) yet. Keep using your saved limit, or set one manually in Profile.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
            .padding(12)
            .background(AppColors.danger.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 10) {
                Button(action: onKeepMine) {
                    Text("Got it")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                Button(action: onDontAskAgain) {
                    Text("Don't check again")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Action stack

    @ViewBuilder private func actions(applyCountry: LegalBACLimit) -> some View {
        VStack(spacing: 10) {
            Button {
                onApply(applyCountry)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                    Text("Apply \(applyCountry.name)'s limit")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            if let current = currentCountry, current.countryCode != applyCountry.countryCode {
                Button(action: onKeepMine) {
                    HStack(spacing: 6) {
                        Text(current.flagEmoji)
                        Text("Keep \(current.name)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onKeepMine) {
                    Text("Not now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Button(action: onDontAskAgain) {
                Text("Don't check again")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    @ViewBuilder private func limitRow(label: String, icon: String, value: Double, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlight ? AppColors.accent : AppColors.textSecondary)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 13, weight: highlight ? .semibold : .regular))
                .foregroundStyle(highlight ? AppColors.text : AppColors.textSecondary)
            Spacer()
            Text(value == 0 ? "0.00%" : String(format: "%.2f%%", value))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(value == 0 ? AppColors.danger : (highlight ? AppColors.accent : AppColors.text))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(highlight ? AppColors.accent.opacity(0.06) : Color.clear)
    }

    private func flagEmoji(for code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { s -> String? in
            guard s.value >= 65, s.value <= 90 else { return nil }
            return UnicodeScalar(127397 + s.value).map { String($0) }
        }.joined()
    }
}
