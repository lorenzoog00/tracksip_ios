import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void
    @State private var scrolledToBottom = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Disclaimer")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                    Spacer()
                }
                .padding()

                Divider().background(AppColors.border)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("⚠️ Important Safety Notice")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.danger)

                        disclaimerText

                        Color.clear.frame(height: 1)
                            .onAppear { scrolledToBottom = true }
                    }
                    .padding()
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 14))
                }

                Divider().background(AppColors.border)

                Button {
                    onAccept()
                } label: {
                    Text("I Understand — Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(scrolledToBottom ? AppColors.accent : AppColors.border)
                        .foregroundStyle(scrolledToBottom ? Color.black : AppColors.textTertiary)
                        .cornerRadius(14)
                }
                .disabled(!scrolledToBottom)
                .padding()
            }
        }
    }

    private var disclaimerText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SipTrack is a tool for informational purposes only. BAC (Blood Alcohol Content) estimates are approximations based on the Widmark formula and are NOT a substitute for professional medical advice or law enforcement testing.")
            Text("Do NOT use this app to determine whether you are safe to drive. Impairment can occur at BAC levels below legal limits. Always arrange safe transportation if you have consumed alcohol.")
            Text("Individual BAC is influenced by many factors including food intake, medications, metabolism, and health conditions that this app cannot account for.")
            Text("By continuing, you agree that you use this app at your own risk and that the developers are not liable for any consequences arising from its use.")
        }
    }
}
