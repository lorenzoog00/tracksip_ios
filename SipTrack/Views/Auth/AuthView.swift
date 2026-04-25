import SwiftUI

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

                    // Header
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

                    // Fields
                    VStack(spacing: 12) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .styledInput()

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .styledInput()
                    }

                    // Feedback
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

                    // Submit
                    Button {
                        Task { await submit() }
                    } label: {
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

                    // Toggle
                    Button {
                        withAnimation {
                            isSignUp.toggle()
                            errorMsg   = nil
                            successMsg = nil
                        }
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

    private var canSubmit: Bool {
        !isLoading && !email.isEmpty && password.count >= 6
    }

    private func submit() async {
        isLoading  = true
        errorMsg   = nil
        successMsg = nil
        do {
            if isSignUp {
                try await supabase.signUp(email: email, password: password)
                successMsg = "Check your email to confirm your account, then sign in."
                isSignUp   = false
            } else {
                try await supabase.signIn(email: email, password: password)
                let data = await supabase.pullUserData()
                appState.applyCloudData(data)
                dismiss()
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Input style modifier

private extension View {
    func styledInput() -> some View {
        self
            .padding(14)
            .background(AppColors.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
            .foregroundStyle(AppColors.text)
    }
}
