import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject var firebase: FirebaseManager

    let email: String
    let password: String
    let onVerified: () -> Void

    @State private var isChecking  = false
    @State private var isResending = false
    @State private var errorMsg: String? = nil
    @State private var resendSuccess = false

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.accent)

                    Text("Verify your email")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppColors.text)

                    VStack(spacing: 6) {
                        Text("We sent a verification link to")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(email)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                    }

                    Text("Open the link in the email, then come back and tap the button below.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text("Can't find it? Check your spam folder.")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.top, 4)
                }

                Spacer()

                VStack(spacing: 14) {
                    if let err = errorMsg {
                        Text(err)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.danger)
                            .multilineTextAlignment(.center)
                    }

                    if resendSuccess {
                        Text("Verification email resent.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.accent)
                    }

                    Button {
                        Task { await checkVerified() }
                    } label: {
                        HStack(spacing: 8) {
                            if isChecking { ProgressView().tint(.black).scaleEffect(0.8) }
                            Text("I've verified my email")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .foregroundStyle(.black)
                        .cornerRadius(14)
                    }
                    .disabled(isChecking || isResending)

                    Button {
                        Task { await resend() }
                    } label: {
                        HStack(spacing: 6) {
                            if isResending { ProgressView().scaleEffect(0.7) }
                            Text("Resend email")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.accent)
                        }
                    }
                    .disabled(isChecking || isResending)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func checkVerified() async {
        isChecking = true; errorMsg = nil
        do {
            let verified = try await firebase.checkEmailVerified(email: email, password: password)
            if verified {
                onVerified()
            } else {
                errorMsg = "Email not verified yet. Check your inbox and tap the link first."
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        isChecking = false
    }

    private func resend() async {
        isResending = true; errorMsg = nil; resendSuccess = false
        do {
            try await firebase.resendVerificationEmail(email: email, password: password)
            resendSuccess = true
        } catch {
            errorMsg = error.localizedDescription
        }
        isResending = false
    }
}
