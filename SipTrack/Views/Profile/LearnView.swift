import SwiftUI

// MARK: - Learn View

struct LearnView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Hero
                    LearnHero()
                        .padding(.bottom, 28)

                    // BAC scale strip
                    BACScaleCard()
                        .padding(.horizontal)
                        .padding(.bottom, 24)

                    // Accordion cards
                    VStack(spacing: 10) {
                        LearnCard(
                            icon: "drop.fill",
                            iconColor: AppColors.water,
                            title: "What is BAC?",
                            bodyText: "Blood Alcohol Concentration (BAC) measures the percentage of alcohol by weight in your bloodstream. A BAC of 0.08% means there are 0.08 grams of alcohol per 100 mL of blood.\n\nAlcohol enters the bloodstream through the stomach and small intestine. Peak BAC typically occurs 30–90 minutes after drinking, depending on whether you've eaten and how quickly you drank.",
                            sources: [
                                ("NIAAA", "https://www.niaaa.nih.gov/publications/brochures-and-fact-sheets/drinking-levels-defined"),
                                ("CDC", "https://www.cdc.gov/alcohol/fact-sheets/alcohol-use.htm"),
                            ]
                        )

                        LearnCard(
                            icon: "function",
                            iconColor: AppColors.accent,
                            title: "How SipTrack estimates your BAC",
                            bodyText: "SipTrack uses the Widmark formula — the gold standard in forensic toxicology since 1932.\n\nBAC = (A ÷ (W × r)) − (β × t)\n\n• A — grams of pure alcohol consumed\n• W — body weight in kilograms\n• r — distribution ratio (≈ 0.68 for men, 0.55 for women)\n• β — elimination rate (≈ 0.015% per hour)\n• t — hours since drinking started\n\nBiological sex affects r because women generally have a higher body fat percentage and lower total body water, which means alcohol is less diluted. This is why the same drink hits harder per body weight.",
                            sources: [
                                ("Widmark 1932", "https://pubmed.ncbi.nlm.nih.gov/"),
                                ("NIAAA Tech Report", "https://www.niaaa.nih.gov/research/guidelines-and-resources/recommended-alcohol-questions"),
                            ]
                        )

                        LearnCard(
                            icon: "car.fill",
                            iconColor: Color(hex: "#FF6348"),
                            title: "Legal limits around the world",
                            bodyText: "Most countries set the legal driving limit at 0.05–0.08% BAC. The US, Canada, and UK use 0.08%. Most of Europe and Australia use 0.05%. Some countries (Sweden, Norway, Japan) use 0.02% — effectively zero tolerance.\n\nThese limits exist because research consistently shows that driving ability begins to degrade at even low BAC levels. At 0.05%, reaction time and steering control are measurably impaired even if you feel fine.",
                            sources: [
                                ("NHTSA", "https://www.nhtsa.gov/risky-driving/drunk-driving"),
                                ("WHO Road Safety", "https://www.who.int/publications/i/item/9789241564397"),
                            ]
                        )

                        LearnCard(
                            icon: "slider.horizontal.3",
                            iconColor: Color(hex: "#E8834A"),
                            title: "What affects how drunk you get",
                            bodyText: "Many variables influence your BAC beyond just the number of drinks:\n\n• Body weight — more mass dilutes alcohol in a larger volume of water\n• Biological sex — women typically reach higher BAC from the same amount\n• Food — a full stomach slows alcohol absorption significantly (peak BAC can drop 30–50%)\n• Rate of drinking — faster consumption overwhelms your liver's elimination rate\n• Hydration — dehydration doesn't raise your BAC but intensifies the physical effects\n• Medications — many common drugs interact with alcohol; always check with your doctor\n• Fatigue — a tired body feels the effects more intensely at any BAC level",
                            sources: [
                                ("NIAAA", "https://www.niaaa.nih.gov/alcohols-effects-health/alcohol-topics/alcohol-facts-and-statistics"),
                                ("Mayo Clinic", "https://www.mayoclinic.org/healthy-lifestyle/nutrition-and-healthy-eating/in-depth/alcohol/art-20044551"),
                            ]
                        )

                        LearnCard(
                            icon: "heart.fill",
                            iconColor: AppColors.success,
                            title: "Low-risk drinking guidelines",
                            bodyText: "The NIAAA defines low-risk drinking as:\n\n• No more than 4 drinks on any single day\n• No more than 14 drinks per week (men)\n• No more than 3 drinks on any single day\n• No more than 7 drinks per week (women)\n\nThe WHO states there is no safe level of alcohol consumption for health — any amount carries some risk. Lower is always better. These guidelines describe thresholds where risk of alcohol-related harm is statistically low, not zero.\n\nIf you're pregnant, on medications, have a family history of addiction, or have a liver condition, even small amounts may be inadvisable.",
                            sources: [
                                ("NIAAA Guidelines", "https://www.rethinkingdrinking.niaaa.nih.gov/How-much-is-too-much/Is-your-drinking-pattern-risky/Whats-Low-Risk-Drinking.aspx"),
                                ("WHO Alcohol", "https://www.who.int/news-room/fact-sheets/detail/alcohol"),
                            ]
                        )

                        LearnCard(
                            icon: "waveform.path.ecg",
                            iconColor: Color(hex: "#BF5AF2"),
                            title: "Long-term effects of regular drinking",
                            bodyText: "Regular heavy drinking affects multiple organ systems:\n\n• Liver — fatty liver, hepatitis, cirrhosis\n• Brain — memory impairment, reduced grey matter volume over years\n• Cardiovascular — increased blood pressure, irregular heartbeat, cardiomyopathy\n• Cancer risk — alcohol is classified as a Group 1 carcinogen by the IARC, linked to cancers of the mouth, throat, esophagus, liver, colon, and breast\n• Mental health — alcohol is a depressant that worsens anxiety and depression over time, even if it feels calming short-term\n\nSipTrack is designed to help you stay aware of your patterns — not to enable unsafe drinking.",
                            sources: [
                                ("IARC Monographs", "https://monographs.iarc.who.int/"),
                                ("CDC Long-term", "https://www.cdc.gov/alcohol/fact-sheets/alcohol-use.htm"),
                                ("NIAAA Health", "https://www.niaaa.nih.gov/alcohols-effects-health/alcohols-effects-body"),
                            ]
                        )
                    }
                    .padding(.horizontal)

                    // Disclaimer
                    DisclaimerCard()
                        .padding(.horizontal)
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("About Alcohol & BAC")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Hero

private struct LearnHero: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.water.opacity(0.1))
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(AppColors.water.opacity(0.07))
                    .frame(width: 60, height: 60)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.water)
            }

            VStack(spacing: 6) {
                Text("Know What You're Drinking")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.text)
                    .multilineTextAlignment(.center)

                Text("Science-backed information about alcohol,\nBAC, and what it means for your body.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal)
    }
}

// MARK: - BAC Scale Card

private struct BACScaleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("INTOXICATION STAGES")
                .font(.system(size: 9, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(AppColors.textTertiary)

            LinearGradient(
                colors: IntoxicationStage.all.map { $0.color },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 4)
            .cornerRadius(2)

            VStack(spacing: 8) {
                ForEach(IntoxicationStage.all, id: \.name) { stage in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(stage.color)
                            .frame(width: 8, height: 8)

                        Text(stage.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(stage.color)
                            .frame(width: 72, alignment: .leading)

                        Text(String(format: "%.2f–%.2f%%", stage.minBAC, stage.maxBAC))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textTertiary)

                        Spacer()

                        Text(stage.blurb)
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .premiumCard(radius: 18)
    }
}

// MARK: - Accordion card

private struct LearnCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let bodyText: String
    let sources: [(String, String)]

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(iconColor.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(iconColor)
                    }

                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [iconColor.opacity(0.3), AppColors.border.opacity(0.3)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 16)

                    Text(bodyText)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)

                    if !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SOURCES")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(2.5)
                                .foregroundStyle(AppColors.textTertiary)
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(sources, id: \.0) { (label, urlStr) in
                                        if let url = URL(string: urlStr) {
                                            Link(destination: url) {
                                                HStack(spacing: 4) {
                                                    Text(label)
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(AppColors.accent)
                                                    Image(systemName: "arrow.up.right")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(AppColors.accent.opacity(0.7))
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppColors.accentDim)
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
                                                )
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [AppColors.surfaceTop, AppColors.surfaceBottom],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                if expanded { iconColor.opacity(0.025) }
            }
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            expanded ? iconColor.opacity(0.35) : AppColors.rimLight,
                            AppColors.border.opacity(0.6)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Disclaimer

private struct DisclaimerCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textTertiary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Not medical advice")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Text("SipTrack's BAC estimates are approximations based on mathematical models. Individual physiology varies. Never rely solely on this app to determine if you are safe to drive. If in doubt, don't drive.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border.opacity(0.6), lineWidth: 1))
    }
}
