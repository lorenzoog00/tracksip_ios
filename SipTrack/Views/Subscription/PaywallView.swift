import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textTertiary)

                    VStack(spacing: 8) {
                        Text("Pro Feature")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.text)
                        Text("Unlock this and all Pro features with a SipTrack Pro subscription.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()

                    NavigationLink(value: Route.subscription) {
                        Text("Unlock with Pro")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.accent)
                            .foregroundStyle(.black)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal)

                    Button { dismiss() } label: {
                        Text("Not Now")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Upgrade to Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}
