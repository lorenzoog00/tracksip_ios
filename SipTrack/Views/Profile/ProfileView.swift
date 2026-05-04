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
    @State private var liveActivityDrinkIds: [String]

    @State private var saveState: SaveState = .idle
    @State private var showDiscardAlert = false
    @State private var showDeleteAccountConfirm = false
    @State private var deletingAccount = false
    @State private var deleteError: String? = nil

    enum SaveState { case idle, saving, saved }

    init() {
        let p = DataStore.shared.loadUserProfile()
        _sex                  = State(initialValue: p.sex)
        _weightStr            = State(initialValue: "\(Int(p.weightKg))")
        _heightStr            = State(initialValue: p.heightCm.map { "\(Int($0))" } ?? "")
        _birthYearStr         = State(initialValue: p.birthYear.map { "\($0)" } ?? "")
        _bacLimit             = State(initialValue: p.bacLimit)
        _waterSuggestions     = State(initialValue: p.waterSuggestions)
        _notificationsEnabled = State(initialValue: p.notifications.enabled)
        _drinksPerHour        = State(initialValue: p.notifications.drinksPerHour)
        _caloriesPerNight     = State(initialValue: p.notifications.caloriesPerNight)
        _bacApproachWarning   = State(initialValue: p.notifications.bacApproachWarning)
        _stageChangeWarning   = State(initialValue: p.notifications.stageChangeWarning)
        _liveActivityDrinkIds = State(initialValue: p.liveActivityDrinkIds)
    }

    // MARK: - Dirty detection

    private var hasChanges: Bool {
        let p = appState.userProfile
        return sex != p.sex
            || (Double(weightStr) ?? p.weightKg) != p.weightKg
            || Double(heightStr) != p.heightCm
            || Int(birthYearStr) != p.birthYear
            || bacLimit != p.bacLimit
            || waterSuggestions != p.waterSuggestions
            || notificationsEnabled != p.notifications.enabled
            || drinksPerHour != p.notifications.drinksPerHour
            || caloriesPerNight != p.notifications.caloriesPerNight
            || bacApproachWarning != p.notifications.bacApproachWarning
            || stageChangeWarning != p.notifications.stageChangeWarning
            || liveActivityDrinkIds != p.liveActivityDrinkIds
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 6) {

                    // MARK: Avatar header

                    avatarHeader
                        .padding(.bottom, 12)

                    // MARK: Subscription banner
                    NavigationLink(value: Route.subscription) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.accentDim)
                                    .frame(width: 36, height: 36)
                                Image(systemName: appState.isPro ? "crown.fill" : "crown")
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppColors.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.isPro ? "Tracksip Pro" : "Upgrade to Pro")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.accent)
                                Text(appState.isPro ? "All features unlocked" : "Unlock all features")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(14)
                        .background(
                            LinearGradient(
                                colors: [AppColors.accentDim, AppColors.accentDim.opacity(0.5)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // MARK: Body Metrics
                    ProfileSection(title: "Body Metrics", icon: "person.fill") {
                        pickerRow(label: "Biological Sex") {
                            Picker("Sex", selection: $sex) {
                                ForEach(Sex.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        ProfileDivider()
                        numRow(label: "Weight", unit: "kg", text: $weightStr, placeholder: "70")
                        ProfileDivider()
                        numRow(label: "Height", unit: "cm", text: $heightStr, placeholder: "175", optional: true)
                        ProfileDivider()
                        numRow(label: "Birth Year", unit: nil, text: $birthYearStr, placeholder: "1995", optional: true)
                    }

                    // MARK: BAC Settings
                    ProfileSection(title: "Driving", icon: "car.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Default BAC limit")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                                Spacer()
                            }
                            Picker("BAC Limit", selection: $bacLimit) {
                                Text("0.05% — Conservative").tag(0.05)
                                Text("0.08% — Standard").tag(0.08)
                            }
                            .pickerStyle(.segmented)
                            Text("Used when driving mode is on during an event.")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }

                    // MARK: Hydration
                    ProfileSection(title: "Hydration", icon: "drop.fill") {
                        Toggle(isOn: $waterSuggestions) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Water reminders")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                                Text("Nudges to drink water between alcoholic drinks")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.accent)
                    }

                    // MARK: Warnings
                    ProfileSection(title: "Warnings", icon: "bell.fill") {
                        Toggle(isOn: $notificationsEnabled) {
                            Text("Enable in-app warnings")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.text)
                        }
                        .tint(AppColors.accent)

                        if notificationsEnabled {
                            ProfileDivider()
                            stepperRow(label: "Drinks per hour limit", value: $drinksPerHour, range: 1...10)
                            ProfileDivider()
                            stepperRow(label: "Calories per night limit", value: $caloriesPerNight, range: 200...2000)
                            ProfileDivider()
                            Toggle(isOn: $bacApproachWarning) {
                                Text("BAC approach warning")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                            }
                            .tint(AppColors.accent)
                            ProfileDivider()
                            Toggle(isOn: $stageChangeWarning) {
                                Text("Stage change warning")
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                            }
                            .tint(AppColors.accent)
                        }
                    }

                    // MARK: Lock Screen
                    if #available(iOS 16.2, *) {
                        ProfileSection(title: "Lock Screen Drinks", icon: "lock.fill") {
                            Text("Up to 3 quick-add buttons on your Lock Screen and Dynamic Island.")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.bottom, 4)

                            ForEach(Array(appState.allDrinkTypes.enumerated()), id: \.element.id) { idx, dt in
                                if idx > 0 { ProfileDivider() }
                                Button {
                                    if liveActivityDrinkIds.contains(dt.id) {
                                        liveActivityDrinkIds.removeAll { $0 == dt.id }
                                    } else if liveActivityDrinkIds.count < 3 {
                                        liveActivityDrinkIds.append(dt.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: dt.sfSymbol)
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppColors.accent)
                                            .frame(width: 20)
                                        Text(dt.name)
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppColors.text)
                                        Spacer()
                                        if liveActivityDrinkIds.contains(dt.id) {
                                            let pos = (liveActivityDrinkIds.firstIndex(of: dt.id) ?? 0) + 1
                                            Text("\(pos)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.black)
                                                .frame(width: 22, height: 22)
                                                .background(AppColors.accent)
                                                .clipShape(Circle())
                                        } else if liveActivityDrinkIds.count >= 3 {
                                            Image(systemName: "circle")
                                                .font(.system(size: 18))
                                                .foregroundStyle(AppColors.border)
                                        } else {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 18))
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // MARK: Account
                    ProfileSection(title: "Account", icon: "person.circle.fill") {
                        if supabase.isSignedIn {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle().fill(AppColors.accentDim).frame(width: 36, height: 36)
                                    Image(systemName: "icloud.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppColors.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Cloud sync active")
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
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppColors.dangerDim)
                                        .cornerRadius(8)
                                }
                            }

                            ProfileDivider()

                            Button(role: .destructive) {
                                showDeleteAccountConfirm = true
                            } label: {
                                HStack(spacing: 10) {
                                    if deletingAccount {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 13))
                                    }
                                    Text(deletingAccount ? "Deleting…" : "Delete Account")
                                        .font(.system(size: 14))
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

                            Text("Permanently removes your account and all cloud data.")
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            NavigationLink(value: Route.auth) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(AppColors.surface).frame(width: 36, height: 36)
                                        Image(systemName: "icloud.slash.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Sign in to sync")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppColors.text)
                                        Text("Back up your data across devices")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }
                    }

                    // MARK: Legal
                    ProfileSection(title: "Legal", icon: "doc.text.fill") {
                        Link(destination: URL(string: "https://looqs.online/siptrack/policy")!) {
                            legalRow(label: "Privacy Policy")
                        }
                        ProfileDivider()
                        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                            legalRow(label: "Terms of Use")
                        }
                    }

                    Color.clear.frame(height: hasChanges ? 100 : 32)
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)

            // MARK: Sticky save bar
            if hasChanges {
                saveBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: hasChanges)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDiscardAlert = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .medium))
                            Text("Back")
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .foregroundStyle(AppColors.accent)
            }
        }
        .onAppear { loadFromProfile(appState.userProfile) }
        .alert("Discard changes?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your unsaved changes will be lost.")
        }
        .confirmationDialog("Delete account?", isPresented: $showDeleteAccountConfirm, titleVisibility: .visible) {
            Button("Delete forever", role: .destructive) {
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent. Your cloud account, events, drinks, and profile will be erased.")
        }
    }

    // MARK: - Sub-views

    private var avatarHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppColors.accentDim)
                    .frame(width: 72, height: 72)
                Image(systemName: "person.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(AppColors.accent)
            }
            if let email = supabase.userEmail {
                Text(email)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.top, 8)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider().background(AppColors.border)
            HStack(spacing: 12) {
                Button {
                    withAnimation { loadFromProfile(appState.userProfile) }
                } label: {
                    Text("Discard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.surface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
                }

                Button { saveProfile() } label: {
                    Group {
                        switch saveState {
                        case .saving:
                            ProgressView().tint(.black)
                        case .saved:
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                Text("Saved!")
                            }
                            .font(.system(size: 15, weight: .bold))
                        case .idle:
                            Text("Save Changes")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [AppColors.accentWarm, AppColors.accent],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.black)
                    .cornerRadius(14)
                    .shadow(color: AppColors.accentGlow, radius: 10, y: 3)
                }
                .disabled(saveState == .saving)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(AppColors.background)
        }
    }

    @ViewBuilder
    private func legalRow(label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.text)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func pickerRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
                .kerning(0.5)
            content()
        }
    }

    @ViewBuilder
    private func numRow(label: String, unit: String?, text: Binding<String>, placeholder: String, optional: Bool = false) -> some View {
        HStack {
            Text(label + (optional ? " (optional)" : ""))
                .font(.system(size: 14))
                .foregroundStyle(optional ? AppColors.textSecondary : AppColors.text)
            Spacer()
            HStack(spacing: 4) {
                TextField(placeholder, text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.text)
                    .frame(width: 60)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func stepperRow(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.text)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
                .foregroundStyle(AppColors.text)
        }
    }

    // MARK: - Logic

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
        liveActivityDrinkIds = p.liveActivityDrinkIds
    }

    private func saveProfile() {
        saveState = .saving
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
        profile.liveActivityDrinkIds = liveActivityDrinkIds
        appState.updateUserProfile(profile)
        withAnimation { saveState = .saved }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { saveState = .idle }
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
}

// MARK: - Supporting Views

private struct ProfileSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .kerning(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
            .background(AppColors.surface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Divider()
            .background(AppColors.border)
            .padding(.vertical, 2)
    }
}

// MARK: - Auth View

struct AuthView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var email     = ""
    @State private var password  = ""
    @State private var isSignUp  = false
    @State private var isLoading = false
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
                        Text(err).font(.system(size: 13)).foregroundStyle(AppColors.danger).multilineTextAlignment(.center)
                    }
                    if let ok = successMsg {
                        Text(ok).font(.system(size: 13)).foregroundStyle(AppColors.success).multilineTextAlignment(.center)
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
                    appState.shouldShowAuth = false
                    dismiss()
                } else {
                    successMsg = "Account created. Check your email to confirm, then sign in."
                    isSignUp = false
                }
            } else {
                try await supabase.signIn(email: email, password: password)
                let data = await supabase.pullUserData()
                appState.applyCloudData(data)
                appState.shouldShowAuth = false
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
