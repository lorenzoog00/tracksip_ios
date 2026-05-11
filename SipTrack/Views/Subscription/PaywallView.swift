import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: StoreManager
    @State private var selectedPeriod: SubscriptionPeriod = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String? = nil

    private let proFeatures: [(String, String, String)] = [
        ("brain.head.profile", "Unlimited AI night reports",  "Free is 5/month. Pro gets every night analyzed."),
        ("calendar",           "Full calendar history",       "See every night, every drink, forever."),
        ("chart.bar.fill",     "Stats & trends",              "Weekly trends, monthly totals, your patterns."),
        ("trophy.fill",        "Challenges & goals",          "Set weekly limits and crush them."),
        ("wineglass.fill",     "Custom drinks",               "Save your favorites for one-tap logging."),
        ("flame.fill",         "Calorie equivalencies",       "How many pizza slices was that night, really?"),
        ("infinity",           "Unlimited event history",     "Free is capped at 30 days. Pro keeps it all."),
        ("doc.text.fill",      "PDF health export",           "Export your full night report as a PDF."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero
                        VStack(spacing: 12) {
                            ZStack {
                                Ellipse()
                                    .fill(
                                        RadialGradient(
                                            colors: [AppColors.accent.opacity(0.28), .clear],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 70
                                        )
                                    )
                                    .frame(width: 160, height: 120)
                                    .blur(radius: 14)

                                Image(systemName: "crown.fill")
                                    .font(.system(size: 58))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [AppColors.accentWarm, AppColors.accent],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: AppColors.accent.opacity(0.55), radius: 20, y: 4)
                            }
                            Text("Tracksip Pro")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.text, AppColors.textWarm],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Track smarter. Drink smarter.")
                                .font(.system(size: 15))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .padding(.top, 24)

                        // Features
                        VStack(spacing: 12) {
                            ForEach(proFeatures, id: \.1) { icon, title, sub in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: icon)
                                        .font(.system(size: 16))
                                        .foregroundStyle(AppColors.accent)
                                        .frame(width: 28, height: 28)
                                        .background(AppColors.accentDim)
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppColors.text)
                                        Text(sub)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                        .premiumCard(radius: 16)
                        .padding(.horizontal)

                        if appState.isPro {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColors.success)
                                Text("You're on Pro — thanks!")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.success)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.successDim)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        } else if store.isLoadingProducts {
                            ProgressView("Loading plans…")
                                .tint(AppColors.accent)
                                .padding()
                        } else if store.products.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(AppColors.danger)
                                Text(store.loadError ?? "Could not load plans")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Button("Try Again") { store.retryLoadProducts() }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.accent)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 20)
                                    .background(AppColors.accentDim)
                                    .cornerRadius(8)
                                #if DEBUG
                                Button("DEBUG: Unlock Pro") {
                                    store.debugUnlockPro()
                                    appState.syncSubscriptionFromStore()
                                    dismiss()
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textTertiary)
                                #endif
                            }
                            .padding()
                        } else {
                            // Period selector
                            VStack(spacing: 10) {
                                ForEach([SubscriptionPeriod.yearly, .monthly], id: \.self) { period in
                                    PeriodOption(
                                        period: period,
                                        product: store.product(for: period),
                                        isSelected: selectedPeriod == period
                                    ) {
                                        selectedPeriod = period
                                    }
                                }
                            }
                            .padding(.horizontal)

                            // Purchase
                            Button {
                                Task { await purchase() }
                            } label: {
                                Group {
                                    if isPurchasing {
                                        ProgressView().tint(.black)
                                    } else {
                                        Text(purchaseLabel)
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    LinearGradient(
                                        colors: [AppColors.accentWarm, AppColors.accent],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundStyle(.black)
                                .cornerRadius(14)
                                .shadow(color: AppColors.accent.opacity(0.55), radius: 16, y: 6)
                                .shadow(color: AppColors.accent.opacity(0.18), radius: 32, y: 10)
                            }
                            .disabled(isPurchasing || store.product(for: selectedPeriod) == nil)
                            .padding(.horizontal)

                            if let err = errorMessage {
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.danger)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }

                            // Cancel anytime
                            HStack(spacing: 6) {
                                Image(systemName: "shield.checkered")
                                    .font(.system(size: 11))
                                Text("Cancel anytime · Auto-renews until cancelled")
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(AppColors.textTertiary)

                            // Restore
                            Button {
                                Task {
                                    await store.restorePurchases()
                                    appState.syncSubscriptionFromStore()
                                }
                            } label: {
                                Text("Restore Purchases")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            #if DEBUG
                            Divider().padding(.horizontal, 40).opacity(0.3)
                            VStack(spacing: 8) {
                                Button("DEBUG: Unlock Pro") {
                                    store.debugUnlockPro()
                                    appState.syncSubscriptionFromStore()
                                    dismiss()
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)

                                Button("DEBUG: Simulate Free User") {
                                    store.debugDowngradeFree()
                                    var p = appState.userProfile
                                    p.subscriptionTier = .free
                                    p.subscriptionPeriod = nil
                                    p.subscriptionStartedAt = nil
                                    p.aiReportsUsedThisMonth = 0
                                    p.aiReportMonthKey = ""
                                    appState.updateUserProfile(p)
                                    dismiss()
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)

                                Button("DEBUG: Simulate Limit Reached") {
                                    store.debugDowngradeFree()
                                    var p = appState.userProfile
                                    p.subscriptionTier = .free
                                    p.subscriptionPeriod = nil
                                    p.subscriptionStartedAt = nil
                                    let cal = Calendar.current
                                    let y = cal.component(.year, from: Date())
                                    let m = cal.component(.month, from: Date())
                                    p.aiReportMonthKey = String(format: "%04d-%02d", y, m)
                                    p.aiReportsUsedThisMonth = AppState.freeMonthlyReportLimit
                                    appState.updateUserProfile(p)
                                    dismiss()
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(AppColors.textTertiary)
                            }
                            #endif
                        }

                        Color.clear.frame(height: 24)
                    }
                }
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var purchaseLabel: String {
        guard let product = store.product(for: selectedPeriod) else { return "Subscribe" }
        switch selectedPeriod {
        case .yearly:   return "Start Yearly — \(product.displayPrice)/yr"
        case .monthly:  return "Start Monthly — \(product.displayPrice)/mo"
        case .lifetime: return "Get Lifetime — \(product.displayPrice)"
        }
    }

    private func purchase() async {
        guard let product = store.product(for: selectedPeriod) else { return }
        isPurchasing = true
        errorMessage = nil
        let result = await store.purchase(product)
        isPurchasing = false
        switch result {
        case .success:
            var profile = appState.userProfile
            profile.subscriptionTier      = .pro
            profile.subscriptionPeriod    = selectedPeriod
            profile.subscriptionStartedAt = Date()
            appState.updateUserProfile(profile)
            dismiss()
        case .failed(let error):
            errorMessage = error.localizedDescription
        case .cancelled, .pending:
            break
        }
    }
}

private struct PeriodOption: View {
    let period: SubscriptionPeriod
    let product: Product?
    let isSelected: Bool
    let onTap: () -> Void

    private var title: String {
        switch period {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    private var subtitle: String? {
        switch period {
        case .yearly:   return "Save ~17% — $1.67/mo billed annually"
        case .monthly:  return "Billed every month · Cancel anytime"
        case .lifetime: return "One-time payment, forever"
        }
    }

    private var badge: String? { period == .yearly ? "BEST VALUE" : nil }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.accent)
                                .cornerRadius(4)
                        }
                    }
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                Spacer()
                Text(product?.displayPrice ?? "—")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.text)
            }
            .padding(14)
            .premiumCard(
                radius: 14,
                tint: AppColors.accent,
                tintOpacity: isSelected ? 0.08 : 0,
                borderTop: isSelected ? AppColors.accent.opacity(0.7) : AppColors.rimLight,
                borderBottom: isSelected ? AppColors.accent.opacity(0.2) : AppColors.border
            )
        }
    }
}
