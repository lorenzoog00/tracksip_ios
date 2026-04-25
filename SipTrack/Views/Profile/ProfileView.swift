import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var supabase: SupabaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var sex: Sex
    @State private var weightStr: String
    @State private var heightStr: String
    @State private var birthYearStr: String
    @State private var bacLimit: Double
    @State private var waterSuggestions: Bool
    @State private var notificationsEnabled: Bool
    @State private var drinksPerHour: Int
    @State private var caloriesPerNight: Int
    @State private var bacApproachWarning: Bool
    @State private var stageChangeWarning: Bool
    @State private var saved = false

    init() {
        let p = DataStore.shared.loadUserProfile()
        _sex                 = State(initialValue: p.sex)
        _weightStr           = State(initialValue: "\(Int(p.weightKg))")
        _heightStr           = State(initialValue: p.heightCm.map { "\(Int($0))" } ?? "")
        _birthYearStr        = State(initialValue: p.birthYear.map { "\($0)" } ?? "")
        _bacLimit            = State(initialValue: p.bacLimit)
        _waterSuggestions    = State(initialValue: p.waterSuggestions)
        _notificationsEnabled = State(initialValue: p.notifications.enabled)
        _drinksPerHour       = State(initialValue: p.notifications.drinksPerHour)
        _caloriesPerNight    = State(initialValue: p.notifications.caloriesPerNight)
        _bacApproachWarning  = State(initialValue: p.notifications.bacApproachWarning)
        _stageChangeWarning  = State(initialValue: p.notifications.stageChangeWarning)
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {

                    // Body metrics
                    SectionCard(title: "Body Metrics") {
                        pickerField(label: "Biological Sex") {
                            Picker("Sex", selection: $sex) {
                                ForEach(Sex.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        numField(label: "Weight (kg)", text: $weightStr, placeholder: "70")
                        numField(label: "Height (cm, optional)", text: $heightStr, placeholder: "175")
                        numField(label: "Birth Year (optional)", text: $birthYearStr, placeholder: "1995")
                    }

                    // Driving mode defaults
                    SectionCard(title: "BAC Settings") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Default BAC Limit")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                            Picker("BAC Limit", selection: $bacLimit) {
                                Text("0.05%").tag(0.05)
                                Text("0.08%").tag(0.08)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Hydration
                    SectionCard(title: "Hydration") {
                        Toggle(isOn: $waterSuggestions) {
                            Text("Water suggestions")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.text)
                        }
                        .tint(AppColors.accent)
                    }

                    // Notifications
                    SectionCard(title: "Warnings") {
                        Toggle(isOn: $notificationsEnabled) {
                            Text("Enable warnings")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.text)
                        }
                        .tint(AppColors.accent)

                        if notificationsEnabled {
                            Divider().background(AppColors.border)

                            stepperField(label: "Drinks per hour limit", value: $drinksPerHour, range: 1...10)
                            stepperField(label: "Calories per night limit", value: $caloriesPerNight, range: 200...2000)
                            Toggle(isOn: $bacApproachWarning) {
                                Text("BAC approach warning")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.text)
                            }
                            .tint(AppColors.accent)
                            Toggle(isOn: $stageChangeWarning) {
                                Text("Stage change warning")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.text)
                            }
                            .tint(AppColors.accent)
                        }
                    }

                    // Save button
                    Button { saveProfile() } label: {
                        HStack {
                            if saved {
                                Image(systemName: "checkmark")
                            }
                            Text(saved ? "Saved!" : "Save Profile")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .foregroundStyle(.black)
                        .cornerRadius(14)
                    }

                    // Account / Cloud sync
                    SectionCard(title: "Account") {
                        if supabase.isSignedIn {
                            HStack {
                                Image(systemName: "icloud.fill")
                                    .foregroundStyle(AppColors.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Signed in")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.text)
                                    if let email = supabase.userEmail {
                                        Text(email)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    Task { await supabase.signOut() }
                                } label: {
                                    Text("Sign Out")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.danger)
                                }
                            }
                        } else {
                            NavigationLink(value: Route.auth) {
                                HStack {
                                    Image(systemName: "icloud.slash.fill")
                                        .foregroundStyle(AppColors.textSecondary)
                                    Text("Sign in to sync across devices")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppColors.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }
                    }

                    // Subscription link
                    NavigationLink(value: Route.subscription) {
                        HStack {
                            Image(systemName: appState.isPro ? "crown.fill" : "star.fill")
                                .foregroundStyle(AppColors.accent)
                            Text(appState.isPro ? "SipTrack Pro — Active" : "Upgrade to Pro")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(14)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                    }

                    Color.clear.frame(height: 32)
                }
                .padding()
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveProfile() {
        var profile = appState.userProfile
        profile.sex              = sex
        profile.weightKg         = Double(weightStr) ?? profile.weightKg
        profile.heightCm         = Double(heightStr)
        profile.birthYear        = Int(birthYearStr)
        profile.bacLimit         = bacLimit
        profile.waterSuggestions = waterSuggestions
        profile.notifications = NotificationPreferences(
            enabled: notificationsEnabled,
            drinksPerHour: drinksPerHour,
            caloriesPerNight: caloriesPerNight,
            bacApproachWarning: bacApproachWarning,
            stageChangeWarning: stageChangeWarning
        )
        appState.updateUserProfile(profile)
        withAnimation { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { saved = false }
        }
    }

    @ViewBuilder
    private func numField(label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .padding(10)
                .background(AppColors.background)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 1))
                .foregroundStyle(AppColors.text)
        }
    }

    @ViewBuilder
    private func pickerField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
    }

    @ViewBuilder
    private func stepperField(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.text)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
                .foregroundStyle(AppColors.text)
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.bottom, 2)
            content()
        }
        .padding()
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }
}
