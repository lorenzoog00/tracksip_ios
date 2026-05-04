import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var sex: Sex           = .male
    @State private var weightKg: String   = "70"
    @State private var showDisclaimer     = false
    @State private var disclaimerAccepted = false

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
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

                VStack(spacing: 16) {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Weight (kg)", systemImage: "scalemass.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        TextField("e.g. 70", text: $weightKg)
                            .keyboardType(.decimalPad)
                            .padding(12)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                            .foregroundStyle(AppColors.text)
                    }
                }
                .padding(.horizontal)

                Spacer()

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
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView {
                completeOnboarding()
            }
        }
    }

    private var isValid: Bool {
        Double(weightKg) != nil
    }

    private func completeOnboarding() {
        var profile = appState.userProfile
        profile.sex = sex
        profile.weightKg = Double(weightKg) ?? 70
        profile.disclaimerAcceptedAt = Date()
        profile.onboardingComplete = true
        appState.updateUserProfile(profile)
        showDisclaimer = false
    }
}
