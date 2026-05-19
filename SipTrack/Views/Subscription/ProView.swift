import SwiftUI
import StoreKit

// Single consolidated upgrade screen.
// Two presentations:
//   .modal  — used from sheet upsell triggers (HomeView, CoachReportCard, AIReportCard, CompareView).
//             Wraps itself in a NavigationStack and shows a dismiss button.
//   .pushed — used from the Profile menu route (Route.subscription).
//             Renders inside the existing nav stack, no dismiss button.
//
// Same view handles the "already Pro" state — header swaps to a thank-you composition,
// the comparison table is replaced by a compact "Everything you have" grid, and pricing
// is replaced by Manage / Restore utilities.
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
    @State private var scrollY: CGFloat = 0
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
        ZStack {
            AppColors.background.ignoresSafeArea()
            backdropGlow

            ScrollView {
                VStack(spacing: 0) {
                    scrollOffsetReader
                    hero
                        .padding(.top, 24)
                        .padding(.bottom, 32)

                    if appState.isPro {
                        proActiveBody
                    } else {
                        upgradeBody
                    }

                    Color.clear.frame(height: appState.isPro ? 40 : 120)
                }
            }
            .coordinateSpace(name: "proScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollY = $0 }
        }
        .navigationTitle(appState.isPro ? "Membership" : "Tracksip Pro")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { modalDismissButton }
        .safeAreaInset(edge: .bottom) { stickyFooter }
        .onAppear {
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                heroBreath = true
            }
        }
    }

    @ToolbarContentBuilder
    private var modalDismissButton: some ToolbarContent {
        if presentation == .modal {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    private var scrollOffsetReader: some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ScrollOffsetKey.self,
                value: -geo.frame(in: .named("proScroll")).minY
            )
        }
        .frame(height: 0)
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

    // MARK: - Hero

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

            Text(appState.isPro ? "You're on Pro" : "Tracksip Pro")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.text, AppColors.textWarm],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .multilineTextAlignment(.center)

            Text(appState.isPro ? proStatusSubtitle : "Every night, mapped.")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var heroIcon: some View {
        if appState.isPro {
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
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.success)
                    .background(Circle().fill(AppColors.background).frame(width: 24, height: 24))
                    .offset(x: 14, y: -8)
                    .shadow(color: AppColors.success.opacity(0.5), radius: 8)
            }
        } else {
            Image(systemName: "wineglass.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentWarm, AppColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppColors.accent.opacity(0.6), radius: 20, y: 4)
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
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return "\(periodWord) · since \(df.string(from: date))"
    }

    // MARK: - Upgrade body (not Pro)

    private var upgradeBody: some View {
        VStack(spacing: 20) {
            featureGroups
                .padding(.horizontal)

            pricingBlock
                .padding(.horizontal)
        }
    }

    private var featureGroups: some View {
        VStack(spacing: 16) {
            ProFeatureGroup(
                title: "EVERY NIGHT",
                rows: [
                    ProFeature(icon: "drop.fill",          label: "Log a drink, edit, delete", mode: .both),
                    ProFeature(icon: "waveform.path.ecg",  label: "Live BAC curve & warnings", mode: .both),
                    ProFeature(icon: "car.fill",           label: "Country-aware legal limit", mode: .both),
                    ProFeature(icon: "wineglass",          label: "Standard drinks library",   mode: .both),
                    ProFeature(icon: "clock.fill",         label: "Active night & timeline",   mode: .both),
                    ProFeature(icon: "applewatch",         label: "Apple Watch live activity", mode: .both),
                ]
            )

            ProFeatureGroup(
                title: "REMEMBER & RECALL",
                rows: [
                    ProFeature(icon: "calendar",          label: "History",         mode: .value(free: "30d",  pro: "∞")),
                    ProFeature(icon: "brain.head.profile", label: "AI night reports", mode: .value(free: "5/mo", pro: "∞")),
                ]
            )

            ProFeatureGroup(
                title: "UNDERSTAND YOURSELF",
                rows: [
                    ProFeature(icon: "chart.bar.fill",        label: "Full analytics & trends", mode: .proOnly),
                    ProFeature(icon: "calendar.badge.clock",  label: "Calendar heatmap",        mode: .proOnly),
                    ProFeature(icon: "trophy.fill",           label: "Challenges & goals",      mode: .proOnly),
                ]
            )

            ProFeatureGroup(
                title: "YOUR BAR",
                rows: [
                    ProFeature(icon: "wineglass.fill", label: "Custom drinks & editing", mode: .both),
                    ProFeature(icon: "flame.fill",     label: "Calorie equivalencies",   mode: .proOnly),
                    ProFeature(icon: "doc.text.fill",  label: "PDF night export",        mode: .proOnly),
                    ProFeature(icon: "rectangle.slash", label: "Ads",                    mode: .value(free: "Shown", pro: "None")),
                ]
            )
        }
    }

    private var pricingBlock: some View {
        VStack(spacing: 14) {
            if store.isLoadingProducts {
                ProgressView("Loading plans…")
                    .tint(AppColors.accent)
                    .padding(.vertical, 24)
            } else if store.products.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.danger)
                    Text(store.loadError ?? "Could not load plans")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { store.retryLoadProducts() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 18)
                        .background(AppColors.accentDim)
                        .cornerRadius(8)
                }
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach([SubscriptionPeriod.yearly, .monthly], id: \.self) { period in
                        ProPlanCard(
                            period: period,
                            product: store.product(for: period),
                            isSelected: selectedPeriod == period
                        ) {
                            withAnimation(.easeOut(duration: 0.18)) { selectedPeriod = period }
                        }
                    }
                }

                inlineCTA
                    .padding(.top, 4)

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.danger)
                        .multilineTextAlignment(.center)
                }

                legalAndRestore
                    .padding(.top, 6)
            }
        }
    }

    private var inlineCTA: some View {
        Button {
            Task { await purchase() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text(purchaseLabel)
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
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
            .shadow(color: AppColors.accent.opacity(0.5), radius: 16, y: 6)
        }
        .disabled(isPurchasing || store.product(for: selectedPeriod) == nil)
    }

    private var legalAndRestore: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 10))
                Text("Cancel anytime · Auto-renews until cancelled")
                    .font(.system(size: 11))
            }
            .foregroundStyle(AppColors.textTertiary)

            Button {
                Task {
                    await store.restorePurchases()
                    appState.syncSubscriptionFromStore()
                }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
            }

            HStack(spacing: 16) {
                Link("Privacy Policy",
                     destination: URL(string: "https://looqs.online/siptrack/policy")!)
                Link("Terms of Use",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Pro active body

    private var proActiveBody: some View {
        VStack(spacing: 18) {
            proInventoryCard
                .padding(.horizontal)

            proUtilityButtons
                .padding(.horizontal)
        }
    }

    private var proInventoryCard: some View {
        let items: [(String, String)] = [
            ("calendar",             "Unlimited history"),
            ("brain.head.profile",   "Unlimited AI reports"),
            ("chart.bar.fill",       "Full analytics"),
            ("calendar.badge.clock", "Calendar heatmap"),
            ("trophy.fill",          "Challenges & goals"),
            ("wineglass.fill",       "Custom drinks"),
            ("flame.fill",           "Calorie equivalencies"),
            ("doc.text.fill",        "PDF night export"),
            ("xmark.shield.fill",    "No ads"),
            ("applewatch",           "Watch live activity"),
        ]

        return VStack(alignment: .leading, spacing: 0) {
            Text("EVERYTHING YOU HAVE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Image(systemName: item.0)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 26, height: 26)
                            .background(AppColors.accentDim)
                            .clipShape(Circle())
                        Text(item.1)
                            .font(.system(size: 12, weight: .medium))
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
                        .font(.system(size: 14, weight: .medium))
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
                    appState.syncSubscriptionFromStore()
                }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Sticky footer (only visible when free + scrolled past hero)

    @ViewBuilder
    private var stickyFooter: some View {
        if !appState.isPro,
           !store.products.isEmpty,
           !store.isLoadingProducts {
            let opacity = min(max((scrollY - 180) / 120, 0), 1)
            let product = store.product(for: selectedPeriod)
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(AppColors.background.opacity(0.6))

                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(AppColors.border)
                    .frame(maxHeight: .infinity, alignment: .top)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stickyPlanLabel.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(AppColors.textTertiary)
                        Text(product?.displayPrice ?? "—")
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.text)
                    }
                    Spacer()
                    Button {
                        Task { await purchase() }
                    } label: {
                        Group {
                            if isPurchasing {
                                ProgressView().tint(.black)
                            } else {
                                Text("Subscribe")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .frame(width: 134, height: 44)
                        .background(
                            LinearGradient(
                                colors: [AppColors.accentWarm, AppColors.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.black)
                        .cornerRadius(12)
                    }
                    .disabled(isPurchasing || product == nil)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .frame(height: 76)
            .opacity(opacity)
            .allowsHitTesting(opacity > 0.5)
        }
    }

    private var stickyPlanLabel: String {
        switch selectedPeriod {
        case .monthly:  return "Monthly"
        case .yearly:   return "Yearly · best value"
        case .lifetime: return "Lifetime"
        }
    }

    // MARK: - Helpers

    private var purchaseLabel: String {
        guard let product = store.product(for: selectedPeriod) else { return "Subscribe" }
        switch selectedPeriod {
        case .yearly:   return "Start Yearly · \(product.displayPrice) / yr"
        case .monthly:  return "Start Monthly · \(product.displayPrice) / mo"
        case .lifetime: return "Get Lifetime · \(product.displayPrice)"
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
            if presentation == .modal { dismiss() }
        case .failed(let error):
            errorMessage = error.localizedDescription
        case .cancelled, .pending:
            break
        }
    }
}

// MARK: - Scroll offset tracking

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Feature model

struct ProFeature: Identifiable {
    enum Mode {
        case both                                      // both columns get a check
        case proOnly                                   // free shows em-dash, pro shows check
        case value(free: String, pro: String)          // tier-specific value (history, AI count, ads…)
    }
    let id = UUID()
    let icon: String
    let label: String
    let mode: Mode
}

// MARK: - Feature group card

struct ProFeatureGroup: View {
    let title: String
    let rows: [ProFeature]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text("FREE")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.textTertiary.opacity(0.8))
                    .frame(width: 52, alignment: .center)
                Text("PRO")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 52, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    ProFeatureRow(feature: row)
                    if idx < rows.count - 1 {
                        Divider()
                            .background(AppColors.border.opacity(0.5))
                            .padding(.leading, 54)
                    }
                }
            }
            .background(AppColors.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
        }
    }
}

// MARK: - Feature row

struct ProFeatureRow: View {
    let feature: ProFeature

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.accent)
                .frame(width: 28, height: 28)
                .background(AppColors.accentDim)
                .clipShape(Circle())

            Text(feature.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.text)

            Spacer(minLength: 8)

            indicator(side: .free)
                .frame(width: 52, alignment: .center)
            indicator(side: .pro)
                .frame(width: 52, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private enum Side { case free, pro }

    @ViewBuilder
    private func indicator(side: Side) -> some View {
        switch feature.mode {
        case .both:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(side == .free
                                 ? AppColors.textSecondary.opacity(0.65)
                                 : AppColors.accent)
        case .proOnly:
            if side == .free {
                Text("—")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.7))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.accent)
            }
        case .value(let free, let pro):
            Text(side == .free ? free : pro)
                .font(.system(size: 11,
                              weight: side == .free ? .medium : .semibold,
                              design: .monospaced))
                .foregroundStyle(side == .free
                                 ? AppColors.textSecondary.opacity(0.75)
                                 : AppColors.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

// MARK: - Plan card

struct ProPlanCard: View {
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
        case .monthly:  return "Flexible · cancel anytime"
        case .yearly:   return "Save ~17% vs monthly"
        case .lifetime: return "One-time payment, forever"
        }
    }

    private var monthlyEquiv: String? {
        guard let p = product, period == .yearly else { return nil }
        let monthly = p.price / 12
        return "≈ \(p.priceFormatStyle.format(monthly))/mo"
    }

    private var isRecommended: Bool { period == .yearly }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.accent : AppColors.border,
                                lineWidth: isSelected ? 2 : 1)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        if isRecommended {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(AppColors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(AppColors.accent, lineWidth: 1)
                                )
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
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.text)
                    if let equiv = monthlyEquiv {
                        Text(equiv)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(16)
            .background(isSelected ? AppColors.accentDim.opacity(0.6) : AppColors.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppColors.accent : AppColors.border,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
