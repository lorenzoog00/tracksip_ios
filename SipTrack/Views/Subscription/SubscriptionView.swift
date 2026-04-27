import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: StoreManager
    @State private var selectedPeriod: SubscriptionPeriod = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String? = nil

    private var sinceLabel: String {
        guard let date = appState.userProfile.subscriptionStartedAt else { return "" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "since \(f.string(from: date))"
    }

    private var periodLabel: String {
        switch appState.userProfile.subscriptionPeriod {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly"
        case .lifetime: return "Lifetime"
        case nil:       return "Pro"
        }
    }

    private let proFeatures: [(String, String)] = [
        ("calendar",       "Full calendar history"),
        ("chart.bar.fill", "Stats & trends"),
        ("trophy.fill",    "Challenges & goals"),
        ("wineglass.fill", "Custom drinks"),
        ("flame.fill",     "Calorie equivalencies"),
        ("clock.fill",     "Unlimited event history"),
    ]

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.accent)
                        Text("SipTrack Pro")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.text)
                        Text("Track smarter. Know more.")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top)

                    // Active status
                    if appState.isPro {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColors.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("You're on Pro")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppColors.success)
                                    Text("\(periodLabel) · \(sinceLabel)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(AppColors.successDim)
                            .cornerRadius(12)

                            if appState.userProfile.subscriptionPeriod != .lifetime {
                                Button {
                                    if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Text("Manage Subscription")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(AppColors.surface)
                                        .cornerRadius(10)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
                                }
                            }
                        }
                    }

                    // Pro features
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(proFeatures, id: \.0) { icon, label in
                            HStack(spacing: 12) {
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.accent)
                                    .frame(width: 22)
                                Text(label)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppColors.text)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .padding(.horizontal)

                    if !appState.isPro {
                        // Period selector
                        if store.products.isEmpty {
                            VStack(spacing: 12) {
                                ProgressView("Loading plans…")
                                    .tint(AppColors.accent)
                                if let err = store.loadError {
                                    Text(err)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppColors.danger)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    Button("Retry") { store.retryLoadProducts() }
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.accent)
                                }
                            }
                            .padding()
                        } else {
                        VStack(spacing: 12) {
                            ForEach([SubscriptionPeriod.monthly, .yearly, .lifetime], id: \.self) { period in
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

                        // Purchase button
                        Button {
                            Task { await purchase() }
                        } label: {
                            Group {
                                if isPurchasing {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text(purchaseLabel)
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.accent)
                            .foregroundStyle(.black)
                            .cornerRadius(14)
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

                        // Restore
                        Button {
                            Task {
                                await store.restorePurchases()
                                appState.syncSubscriptionFromStore()
                            }
                        } label: {
                            Text("Restore Purchases")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        // Legal
                        Text("Payment charged at purchase confirmation. Subscriptions auto-renew unless cancelled 24h before renewal.")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        }
                    }

                    Color.clear.frame(height: 32)
                }
            }
        }
        .navigationTitle("Pro")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var purchaseLabel: String {
        guard let product = store.product(for: selectedPeriod) else { return "Subscribe" }
        switch selectedPeriod {
        case .lifetime: return "Buy Lifetime — \(product.displayPrice)"
        case .yearly:   return "Subscribe Yearly — \(product.displayPrice)/yr"
        case .monthly:  return "Subscribe Monthly — \(product.displayPrice)/mo"
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
            profile.subscriptionTier   = .pro
            profile.subscriptionPeriod = selectedPeriod
            profile.subscriptionStartedAt = Date()
            appState.updateUserProfile(profile)
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

    private var badge: String? {
        period == .yearly ? "Best Value" : nil
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.accent)
                                .cornerRadius(6)
                        }
                    }
                    if period == .yearly {
                        Text("Save ~17% vs monthly")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    } else if period == .lifetime {
                        Text("One-time payment, forever")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                Spacer()
                Text(product?.displayPrice ?? "—")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isSelected ? AppColors.accent : AppColors.text)
            }
            .padding(14)
            .background(isSelected ? AppColors.accentDim : AppColors.surface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}
