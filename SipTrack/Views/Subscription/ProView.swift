import SwiftUI
import StoreKit

// Single consolidated upgrade screen.
// Two presentations:
//   .modal  — used from sheet upsell triggers (HomeView, CoachReportCard, AIReportCard, CompareView).
//             Wraps itself in a NavigationStack and shows a dismiss button.
//   .pushed — used from the Profile menu route (Route.subscription).
//             Renders inside the existing nav stack, no dismiss button.
//
// Free users get `PaywallScreen`, which only draws: this view feeds it the
// StoreKit plans and eligible free trials, and owns purchase and restore.
// Pro members get the membership view instead: a thank-you hero, an
// "Everything you have" grid and Manage / Restore utilities.
struct ProView: View {
    enum Presentation { case modal, pushed }
    let presentation: Presentation

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: StoreManager

    @State private var selectedPeriod: SubscriptionPeriod = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String? = nil
    @State private var heroBreath = false
    /// Free trials the user is eligible for, by period.
    @State private var trials: [SubscriptionPeriod: PaywallTrial] = [:]
    init(presentation: Presentation) {
        self.presentation = presentation
    }

    var body: some View {
        Group {
            if presentation == .modal {
                NavigationStack { content }
            } else {
                content
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if appState.isPro {
                membershipView
            } else {
                paywall
            }
        }
        .navigationTitle(appState.isPro ? "Membership" : "Tracksip Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            modalDismissButton
            restoreButton
        }
        .onChange(of: store.restoreError) { _, message in
            guard let message else { return }
            NoticeCenter.shared.show(Notice(
                icon: "creditcard.fill",
                title: "Purchase update",
                message: message,
                actions: [NoticeAction("OK") { store.restoreError = nil }]
            ))
        }
    }

    @ToolbarContentBuilder
    private var modalDismissButton: some ToolbarContent {
        if presentation == .modal {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    /// Restore on the paywall, in both presentations. Members already have
    /// Restore Purchases in their utilities, running the same closure.
    @ToolbarContentBuilder
    private var restoreButton: some ToolbarContent {
        if !appState.isPro {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.restorePurchases()
                        errorMessage = store.restoreError
                        appState.syncSubscriptionFromStore()
                    }
                } label: {
                    Text("Restore")
                        .foregroundStyle(AppColors.textSecondary)
                }
                .disabled(isPurchasing)
            }
        }
    }

    // MARK: - Paywall (not Pro)

    private var paywall: some View {
        PaywallScreen(
            plans: plans,
            selected: $selectedPeriod,
            isPurchasing: isPurchasing,
            errorMessage: errorMessage,
            onPurchase: { Task { await purchase() } },
            onRetry: { store.retryLoadProducts() }
        )
        // `purchase()` buys `selectedPeriod`, so keep it on the plan the
        // screen shows as selected (Monthly when only Monthly loaded).
        .onChange(of: store.products, initial: true) { _, _ in
            if let period = plans.resolvedSelection(selectedPeriod) {
                selectedPeriod = period
            }
        }
        .task(id: store.products.map(\.id)) { await loadTrials() }
    }

    /// Yearly and Monthly in display form; Lifetime is never offered here.
    private var plans: PaywallPlansState {
        if store.isLoadingProducts { return .loading }
        if store.products.isEmpty { return .failed(store.loadError ?? "Could not load plans") }

        var savings: Int? = nil
        if let yearly = store.product(for: .yearly), let monthly = store.product(for: .monthly) {
            savings = PaywallCopy.savingsPercent(monthly: monthly.price, yearly: yearly.price)
        }

        let options = [SubscriptionPeriod.yearly, .monthly].compactMap { period -> PaywallPlanOption? in
            guard let product = store.product(for: period) else { return nil }
            let isYearly = period == .yearly
            return PaywallPlanOption(
                period: period,
                price: product.displayPrice,
                monthlyEquivalent: isYearly
                    ? "≈ \(product.priceFormatStyle.format(product.price / 12))/mo"
                    : nil,
                savings: isYearly ? savings : nil,
                trial: trials[period]
            )
        }
        return .loaded(options)
    }

    /// The free trial each plan would start. An intro offer the user is no
    /// longer eligible for, or one that isn't a free trial, leaves no entry.
    private func loadTrials() async {
        var found: [SubscriptionPeriod: PaywallTrial] = [:]
        for period in [SubscriptionPeriod.yearly, .monthly] {
            guard let subscription = store.product(for: period)?.subscription else { continue }
            let eligible = await subscription.isEligibleForIntroOffer
            guard eligible,
                  let offer = subscription.introductoryOffer,
                  let trial = PaywallTrial(offer: offer) else { continue }
            found[period] = trial
        }
        // Products changed (a newer task writes instead) or the screen closed.
        guard !Task.isCancelled else { return }
        trials = found
    }

    // MARK: - Membership (Pro)

    private var membershipView: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            backdropGlow

            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 24)
                        .padding(.bottom, 32)

                    proActiveBody

                    Color.clear.frame(height: 40)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                heroBreath = true
            }
        }
    }

    private var backdropGlow: some View {
        VStack {
            Ellipse()
                .fill(AppColors.accent.opacity(0.10))
                .frame(width: 360, height: 200)
                .blur(radius: 80)
                .offset(y: 50)
            Spacer()
        }
        .ignoresSafeArea()
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.accent.opacity(0.32), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 130)
                    .blur(radius: 18)
                    .scaleEffect(heroBreath ? 1.06 : 0.94)
                    .opacity(heroBreath ? 1.0 : 0.7)

                heroIcon
            }
            .frame(height: 100)

            Text("You're on Pro")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.text, AppColors.textWarm],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .multilineTextAlignment(.center)

            Text(proStatusSubtitle)
                .font(.system(size: 17))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var heroIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentWarm, AppColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppColors.accent.opacity(0.55), radius: 18, y: 4)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 24))
                .foregroundStyle(AppColors.success)
                .background(Circle().fill(AppColors.background).frame(width: 24, height: 24))
                .offset(x: 14, y: -8)
                .shadow(color: AppColors.success.opacity(0.5), radius: 8)
        }
    }

    private var proStatusSubtitle: String {
        let p = appState.userProfile
        let periodWord: String = {
            switch p.subscriptionPeriod {
            case .monthly:  return "Monthly"
            case .yearly:   return "Yearly"
            case .lifetime: return "Lifetime"
            case nil:       return "Member"
            }
        }()
        guard let date = p.subscriptionStartedAt else { return periodWord }
        let df = AppDates.formatter("MMMM yyyy")
        return "\(periodWord) · since \(df.string(from: date))"
    }

    private var proActiveBody: some View {
        VStack(spacing: 18) {
            proInventoryCard
                .padding(.horizontal)

            proUtilityButtons
                .padding(.horizontal)
        }
    }

    private var proInventoryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("EVERYTHING YOU HAVE")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(PaywallFeatures.membership, id: \.self) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 26, height: 26)
                            .background(AppColors.accentDim)
                            .clipShape(Circle())
                        Text(feature.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
    }

    private var proUtilityButtons: some View {
        VStack(spacing: 10) {
            if appState.userProfile.subscriptionPeriod != .lifetime {
                Button {
                    if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Manage Subscription")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppColors.surface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                }
            }

            Button {
                Task {
                    await store.restorePurchases()
                    errorMessage = store.restoreError
                    appState.syncSubscriptionFromStore()
                }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 15))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Purchase

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
            if presentation == .modal { dismiss() }
        case .failed(let error):
            errorMessage = error.localizedDescription
        case .cancelled, .pending:
            break
        }
    }
}
