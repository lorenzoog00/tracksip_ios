import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var sex: Sex         = .male
    @State private var weightKg: String = "70"
    @State private var heightCm: String = ""
    @State private var birthYear: String = ""
    @State private var showDisclaimer   = false

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 8) {
                        Text("🍹")
                            .font(.system(size: 60))
                        Text("Welcome to Tracksip")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.text)
                        Text("Set up your profile for accurate BAC estimates.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 48)

                    VStack(spacing: 20) {
                        // Sex
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Biological Sex", systemImage: "person.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            Picker("Sex", selection: $sex) {
                                ForEach(Sex.allCases, id: \.self) { s in
                                    Text(s.rawValue).tag(s)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Weight
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Weight (kg)", systemImage: "scalemass.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            TextField("e.g. 70", text: $weightKg)
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(weightError != nil ? AppColors.danger : AppColors.border, lineWidth: 1))
                                .foregroundStyle(AppColors.text)
                            if let err = weightError {
                                Text(err)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.danger)
                            }
                        }

                        // Height
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Height (cm)", systemImage: "ruler.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                Text("· Optional")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            TextField("e.g. 175", text: $heightCm)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                .foregroundStyle(AppColors.text)
                        }

                        // Birth year
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Birth Year", systemImage: "calendar")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textSecondary)
                                Text("· Optional")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            TextField("e.g. 1995", text: $birthYear)
                                .keyboardType(.numberPad)
                                .padding(12)
                                .background(AppColors.surface)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                .foregroundStyle(AppColors.text)
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button { showDisclaimer = true } label: {
                            Text("Continue")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isValid ? AppColors.accent : AppColors.border)
                                .foregroundStyle(isValid ? Color.black : AppColors.textTertiary)
                                .cornerRadius(14)
                        }
                        .disabled(!isValid)
                        .padding(.horizontal)

                        Text("Your data stays on your device.")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView {
                completeOnboarding()
            }
        }
    }

    private var weightValue: Double? {
        guard let w = Double(weightKg), w >= 30, w <= 300 else { return nil }
        return w
    }

    private var isValid: Bool { weightValue != nil }

    private var weightError: String? {
        guard !weightKg.isEmpty else { return nil }
        if Double(weightKg) == nil { return "Enter a number" }
        if (Double(weightKg) ?? 0) < 30 { return "Must be at least 30 kg" }
        if (Double(weightKg) ?? 0) > 300 { return "Must be under 300 kg" }
        return nil
    }

    private func completeOnboarding() {
        var profile = appState.userProfile
        profile.sex = sex
        profile.weightKg = weightValue ?? 70
        if let h = Double(heightCm), h >= 100, h <= 250 { profile.heightCm = h }
        let currentYear = Calendar.current.component(.year, from: Date())
        if let y = Int(birthYear), y > 1900, y < currentYear { profile.birthYear = y }
        profile.disclaimerAcceptedAt = Date()
        profile.onboardingComplete = true
        appState.updateUserProfile(profile)
        showDisclaimer = false
    }
}
