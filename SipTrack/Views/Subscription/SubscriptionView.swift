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

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            // Ambient glow behind header
            VStack {
                Ellipse()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 320, height: 160)
                    .blur(radius: 60)
                    .offset(y: 40)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // MARK: Hero
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppColors.accentGlow)
                                .frame(width: 90, height: 90)
                                .blur(radius: 20)
                            Image(systemName: "crown.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.accentWarm, AppColors.accent],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }

                        Text("Tracksip Pro")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColors.accentWarm, AppColors.text],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("Drink smarter. Live better.")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 32)

                    // MARK: Active Pro Banner
                    if appState.isPro {
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(AppColors.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("You're on Pro")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.success)
                                    Text("\(periodLabel) · \(sinceLabel)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(AppColors.successDim)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.success.opacity(0.3), lineWidth: 1))

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
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }

                    // MARK: Feature Groups
                    VStack(spacing: 12) {
                        FeatureGroup(title: "Know Your Night", icon: "chart.bar.fill", iconColor: AppColors.accent, features: [
                            FeatureRow(icon: "chart.bar.fill",        title: "Full Analytics",    desc: "All-time stats, trends & weekly breakdowns"),
                            FeatureRow(icon: "calendar",             title: "Calendar Heatmap",  desc: "Visual history of every night, month by month"),
                            FeatureRow(icon: "trophy.fill",          title: "Challenges & Goals", desc: "Set targets and track your progress over time"),
                        ])

                        FeatureGroup(title: "Your Bar, Your Way", icon: "wineglass.fill", iconColor: AppColors.accent, features: [
                            FeatureRow(icon: "wineglass.fill",       title: "Custom Drinks",     desc: "Add anything with exact ABV, volume & calories"),
                            FeatureRow(icon: "flame.fill",           title: "Calorie Insights",  desc: "See every drink as food & exercise equivalents"),
                        ])

                        FeatureGroup(title: "Pure Experience", icon: "sparkles", iconColor: AppColors.accent, features: [
                            FeatureRow(icon: "clock.fill",           title: "Unlimited History", desc: "Access every event, not just the last 30 days"),
                            FeatureRow(icon: "xmark.shield.fill",    title: "Zero Ads",          desc: "A clean, distraction-free experience, always"),
                        ])
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 28)

                    // MARK: Pricing
                    if !appState.isPro {
                        if store.isLoadingProducts {
                            ProgressView("Loading plans…")
                                .tint(AppColors.accent)
                                .padding(40)
                        } else if store.products.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AppColors.danger)
                                Text(store.loadError ?? "Could not load plans")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Button("Try Again") { store.retryLoadProducts() }
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.accent)
                            }
                            .padding(40)
                        } else {
                            VStack(spacing: 16) {

                                // Section header
                                HStack {
                                    Text("Choose your plan")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppColors.text)
                                    Spacer()
                                }
                                .padding(.horizontal)

                                // Plan cards
                                VStack(spacing: 10) {
                                    ForEach([SubscriptionPeriod.monthly, .yearly, .lifetime], id: \.self) { period in
                                        PlanCard(
                                            period: period,
                                            product: store.product(for: period),
                                            isSelected: selectedPeriod == period
                                        ) { selectedPeriod = period }
                                    }
                                }
                                .padding(.horizontal)

                                // CTA
                                Button {
                                    Task { await purchase() }
                                } label: {
                                    Group {
                                        if isPurchasing {
                                            ProgressView().tint(.black)
                                        } else {
                                            Text(purchaseLabel)
                                                .font(.system(size: 17, weight: .bold))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(
                                        LinearGradient(
                                            colors: [AppColors.accentWarm, AppColors.accent],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundStyle(.black)
                                    .cornerRadius(16)
                                    .shadow(color: AppColors.accentGlow, radius: 16, y: 4)
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
                                        .foregroundStyle(AppColors.textTertiary)
                                }

                                // Legal
                                VStack(spacing: 6) {
                                    Text("Payment charged at purchase confirmation. Subscriptions auto-renew unless cancelled 24h before renewal.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(AppColors.textTertiary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)

                                    HStack(spacing: 16) {
                                        Link("Privacy Policy", destination: URL(string: "https://looqs.online/siptrack/policy")!)
                                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                        }

                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .navigationTitle("Pro")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var purchaseLabel: String {
        guard let product = store.product(for: selectedPeriod) else { return "Get Tracksip Pro" }
        switch selectedPeriod {
        case .lifetime: return "Get Lifetime Access — \(product.displayPrice)"
        case .yearly:   return "Start Pro — \(product.displayPrice)/yr"
        case .monthly:  return "Start Pro — \(product.displayPrice)/mo"
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
        case .failed(let error):
            errorMessage = error.localizedDescription
        case .cancelled, .pending:
            break
        }
    }
}

// MARK: - Feature Group

private struct FeatureRow {
    let icon: String
    let title: String
    let desc: String
}

private struct FeatureGroup: View {
    let title: String
    let icon: String
    let iconColor: Color
    let features: [FeatureRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .kerning(0.8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(features.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(AppColors.accentDim)
                                .frame(width: 34, height: 34)
                            Image(systemName: row.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.text)
                            Text(row.desc)
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if idx < features.count - 1 {
                        Divider()
                            .background(AppColors.border)
                            .padding(.leading, 64)
                    }
                }
            }
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
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

    private var subtitle: String {
        switch period {
        case .monthly:  return "Flexible, cancel anytime"
        case .yearly:   return "Save ~17% vs monthly"
        case .lifetime: return "One-time payment, forever"
        }
    }

    private var monthlyEquiv: String? {
        guard let p = product else { return nil }
        switch period {
        case .yearly:
            let monthly = p.price / 12
            return "≈ \(p.priceFormatStyle.format(monthly)) / mo"
        default:
            return nil
        }
    }

    private var isRecommended: Bool { period == .yearly }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 2 : 1)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        if isRecommended {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppColors.accent)
                                .cornerRadius(5)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product?.displayPrice ?? "—")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.text)
                    if let equiv = monthlyEquiv {
                        Text(equiv)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? AppColors.accentDim : AppColors.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? AppColors.accent : AppColors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
    }
}
