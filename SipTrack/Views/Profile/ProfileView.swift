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
    @State private var showDeleteAccountConfirm = false
    @State private var deletingAccount = false
    @State private var deleteError: String? = nil

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

                            Divider().background(AppColors.border)

                            Button(role: .destructive) {
                                showDeleteAccountConfirm = true
                            } label: {
                                HStack {
                                    if deletingAccount {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "trash.fill")
                                    }
                                    Text(deletingAccount ? "Deleting…" : "Delete my account")
                                        .font(.system(size: 14, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(AppColors.danger)
                            }
                            .disabled(deletingAccount)

                            if let err = deleteError {
                                Text(err)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.danger)
                            }

                            Text("Permanently deletes your account and all cloud data (events, drinks, profile).")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
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
        .onAppear { loadFromProfile(appState.userProfile) }
        .confirmationDialog(
            "Delete account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete forever", role: .destructive) {
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent. Your cloud account, events, drinks, and profile will be erased.")
        }
    }

    private func performDeleteAccount() async {
        deletingAccount = true
        deleteError = nil
        if let err = await supabase.deleteAccount() {
            deleteError = err
        }
        deletingAccount = false
    }

    private func loadFromProfile(_ p: UserProfile) {
        sex                  = p.sex
        weightStr            = "\(Int(p.weightKg))"
        heightStr            = p.heightCm.map { "\(Int($0))" } ?? ""
        birthYearStr         = p.birthYear.map { "\($0)" } ?? ""
        bacLimit             = p.bacLimit
        waterSuggestions     = p.waterSuggestions
        notificationsEnabled = p.notifications.enabled
        drinksPerHour        = p.notifications.drinksPerHour
        caloriesPerNight     = p.notifications.caloriesPerNight
        bacApproachWarning   = p.notifications.bacApproachWarning
        stageChangeWarning   = p.notifications.stageChangeWarning
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

// MARK: - Auth View

struct AuthView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var email       = ""
    @State private var password    = ""
    @State private var isSignUp    = false
    @State private var isLoading   = false
    @State private var errorMsg: String?   = nil
    @State private var successMsg: String? = nil

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(AppColors.accent)
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppColors.text)
                        Text("Sync your nights across devices")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .authInput()
                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .authInput()
                    }

                    if let err = errorMsg {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.danger)
                            .multilineTextAlignment(.center)
                    }
                    if let ok = successMsg {
                        Text(ok)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.success)
                            .multilineTextAlignment(.center)
                    }

                    Button { Task { await submit() } } label: {
                        HStack(spacing: 8) {
                            if isLoading { ProgressView().tint(.black).scaleEffect(0.8) }
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSubmit ? AppColors.accent : AppColors.accentDim)
                        .foregroundStyle(.black)
                        .cornerRadius(14)
                    }
                    .disabled(!canSubmit)

                    Button {
                        withAnimation { isSignUp.toggle(); errorMsg = nil; successMsg = nil }
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign In" : "No account? Create one")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
        }
        .navigationTitle(isSignUp ? "Create Account" : "Sign In")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canSubmit: Bool { !isLoading && !email.isEmpty && password.count >= 6 }

    private func submit() async {
        isLoading = true; errorMsg = nil; successMsg = nil
        do {
            if isSignUp {
                let signedInImmediately = try await supabase.signUp(email: email, password: password)
                if signedInImmediately {
                    let data = await supabase.pullUserData()
                    appState.applyCloudData(data)
                    dismiss()
                } else {
                    successMsg = "Account created. Check your email to confirm, then sign in."
                    isSignUp = false
                }
            } else {
                try await supabase.signIn(email: email, password: password)
                let data = await supabase.pullUserData()
                appState.applyCloudData(data)
                dismiss()
            }
        } catch { errorMsg = error.localizedDescription }
        isLoading = false
    }
}

private extension View {
    func authInput() -> some View {
        self
            .padding(14)
            .background(AppColors.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
            .foregroundStyle(AppColors.text)
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

