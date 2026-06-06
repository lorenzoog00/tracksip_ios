import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var firebase: FirebaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var email      = ""
    @State private var isLoading  = false
    @State private var errorMsg: String? = nil
    @State private var sent       = false

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: sent ? "checkmark.circle.fill" : "lock.rotation")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.accent)

                    Text(sent ? "Check your inbox" : "Reset Password")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppColors.text)

                    if sent {
                        VStack(spacing: 6) {
                            Text("We sent a reset link to")
                                .font(.system(size: 15))
                                .foregroundStyle(AppColors.textSecondary)
                            Text(email)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                            Text("Can't find it? Check your spam folder.")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                    } else {
                        Text("Enter your email and we'll send you a link to reset your password.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }

                Spacer()

                VStack(spacing: 14) {
                    if let err = errorMsg {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.danger)
                            .multilineTextAlignment(.center)
                    }

                    if !sent {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding(14)
                            .background(AppColors.surface)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                            .foregroundStyle(AppColors.text)

                        Button {
                            Task { await sendReset() }
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading { ProgressView().tint(.black).scaleEffect(0.8) }
                                Text("Send Reset Link")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(email.isEmpty ? AppColors.accentDim : AppColors.accent)
                            .foregroundStyle(.black)
                            .cornerRadius(14)
                        }
                        .disabled(email.isEmpty || isLoading)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text(sent ? "Back to Sign In" : "Cancel")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendReset() async {
        isLoading = true; errorMsg = nil
        do {
            try await firebase.resetPassword(email: email)
            sent = true
        } catch {
            errorMsg = friendlyAuthError(error)
        }
        isLoading = false
    }
}
