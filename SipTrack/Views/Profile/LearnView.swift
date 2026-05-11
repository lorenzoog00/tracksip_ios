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
                            bodyText: "SipTrack uses the Widmark framework — the forensic standard since 1932 — extended with modern pharmacokinetic refinements that improve accuracy over a vanilla Widmark calculator.\n\nThe baseline equation:\n\nBAC = (A ÷ (W × r)) − (β × t)\n\n• A — grams of pure alcohol consumed (volume × ABV × 0.789)\n• W — body weight in kilograms\n• r — distribution ratio (how much body water the alcohol spreads through)\n• β — elimination rate (how fast your liver clears alcohol)\n• t — hours since drinking started\n\nWhat SipTrack adds on top of the textbook formula:\n\n1. Watson 1980 total-body-water individualisation of r when you've entered your height and birth year. This is more accurate than the population constants 0.68 (men) / 0.55 (women) for people outside the average BMI.\n\n2. Sex-specific β — women clear alcohol about 14% faster than men in the elimination phase (0.0157 vs 0.0138 BAC% / h), measured directly in modern breath-alcohol studies.\n\n3. First-order absorption — alcohol doesn't appear in your blood instantly. SipTrack models the rising curve with an absorption rate constant kA that depends on what's in your stomach.\n\n4. First-pass metabolism — when you eat with alcohol, gastric alcohol dehydrogenase oxidises part of the dose before it reaches your bloodstream. SipTrack subtracts this fraction (10% for a snack, 20% for a full meal, halved for women who have less gastric ADH).\n\n5. Age correction — β decreases about 5% per decade after 60.",
                            sources: [
                                ("Widmark 1932", "https://pubmed.ncbi.nlm.nih.gov/"),
                                ("Searle 2015", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4361698/"),
                                ("JAAPL Forensic 2017", "https://jaapl.org/content/45/4/429"),
                                ("Maskell 2022", "https://onlinelibrary.wiley.com/doi/10.1111/1556-4029.14859"),
                            ]
                        )

                        LearnCard(
                            icon: "fork.knife",
                            iconColor: Color(hex: "#E8834A"),
                            title: "Why food matters — first-pass metabolism",
                            bodyText: "Food doesn't just \"slow alcohol down\" — it removes some of it before it reaches your blood at all.\n\nGastric emptying is the single most important factor controlling alcohol absorption. When your stomach is empty, alcohol passes into the small intestine within minutes and is absorbed quickly. When you've eaten, food slows gastric emptying — and while alcohol sits in the stomach, gastric alcohol dehydrogenase (an enzyme in your stomach lining) metabolises a portion of it. This is called first-pass metabolism (FPM).\n\nSipTrack models three states:\n\n• Empty stomach → absorption half-life ≈ 7 min, 0% FPM, peak BAC reached in 30–60 min.\n• Snack → absorption half-life ≈ 14 min, ~10% FPM, peak reached in 60–90 min.\n• Full meal → absorption half-life ≈ 28 min, ~20% FPM, peak reached in 90–180 min.\n\nA classic FDA \"light breakfast\" reduces the area under the BAC curve by about 36%. A heavy meal reduces it even more. SipTrack accounts for the meal you logged at the start of the night and updates the model every time you add a new food entry — the slowest-absorption / highest-FPM effect still in your stomach wins.\n\nThe stomach effect decays linearly back to \"empty\" over about 150 minutes.",
                            sources: [
                                ("Jones 1996 FPM", "https://pmc.ncbi.nlm.nih.gov/articles/PMC1727307/"),
                                ("Frezza NEJM 1990", "https://www.nejm.org/doi/full/10.1056/NEJM199001113220205"),
                                ("Norberg PK 2003", "https://link.springer.com/article/10.2165/00003088-198713050-00001"),
                            ]
                        )

                        LearnCard(
                            icon: "person.2.fill",
                            iconColor: Color(hex: "#FF6B9D"),
                            title: "Why sex changes the math",
                            bodyText: "Two physiological differences drive the male/female BAC gap, and SipTrack accounts for both:\n\n1. Lower total body water. At the same weight, women have ~10% less total body water than men because of higher body-fat percentage. Alcohol distributes into water, so the same dose reaches a higher concentration. This is the classic Widmark r difference: ~0.68 for men vs ~0.55 for women.\n\n2. Lower gastric alcohol dehydrogenase. Women's stomachs have about 25% less ADH activity (Frezza, NEJM 1990). That means less first-pass metabolism — more of each drink reaches the bloodstream. SipTrack reduces the FPM term for women accordingly.\n\nCounterintuitively, women also eliminate alcohol slightly faster in the post-peak phase: 0.0157 vs 0.0138 BAC%/h in recent breath-alcohol studies. But the higher peak more than offsets the faster clearance — same dose, same weight, women hit a higher peak BAC and stay above the legal limit longer.",
                            sources: [
                                ("Frezza NEJM 1990", "https://www.nejm.org/doi/full/10.1056/NEJM199001113220205"),
                                ("Bissinger 2020", "https://pmc.ncbi.nlm.nih.gov/articles/PMC7518982/"),
                            ]
                        )

                        LearnCard(
                            icon: "chart.bar.fill",
                            iconColor: Color(hex: "#BF5AF2"),
                            title: "Uncertainty — what the number doesn't tell you",
                            bodyText: "No BAC calculator can output a single precise number. Searle (2015) showed the combined coefficient of variation on a Widmark estimate is around 20% — meaning a calculated 0.080% BAC could realistically be anywhere from 0.064% to 0.096%.\n\nThe sources of uncertainty:\n\n• Drink volume and actual ABV (cocktails are notoriously variable).\n• Individual variation in body composition (r factor SD ≈ ±0.085 L/kg).\n• Individual variation in elimination rate (β SD ≈ ±0.003 BAC%/h; up to ±50% in chronic drinkers).\n• How quickly food and drink left your stomach.\n• Whether you're naïve or a regular drinker (enzyme induction).\n\nIn naturalistic comparisons against measured breathalyser BAC, even the best published eBAC formulas only achieve R² ≈ 0.55. SipTrack will sometimes overestimate, sometimes underestimate.\n\nRule of thumb: if the app says you're at 0.07%, treat it as \"probably between 0.055 and 0.085\". Never use it as a green light to drive close to the legal limit.",
                            sources: [
                                ("Searle 2015", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4361698/"),
                                ("Hustad & Carey 2005", "https://pubmed.ncbi.nlm.nih.gov/15830913/"),
                            ]
                        )

                        LearnCard(
                            icon: "drop.degreesign",
                            iconColor: AppColors.water,
                            title: "Does drinking water lower your BAC?",
                            bodyText: "Short answer: no.\n\nWater intake does not pharmacokinetically reduce blood alcohol concentration. Your liver clears ethanol at a roughly fixed rate regardless of how much water you drink. SipTrack does not apply any BAC reduction for water consumption — that would be unscientific.\n\nWhat water does help with:\n\n• Pace. Alternating water with drinks slows down how fast you order the next alcoholic drink, which directly lowers peak BAC.\n• Hangover symptoms. Dehydration accounts for a portion of next-morning misery (headache, dry mouth, fatigue). Water doesn't \"cure\" hangover but it reduces the dehydration component.\n• Hydration coaching. SipTrack tracks your water-to-drinks ratio for healthy-pacing feedback — but the BAC number itself is independent.\n\nIf you've seen apps that lower the BAC reading when you drink water, that's marketing, not pharmacology.",
                            sources: [
                                ("Jones Pharmacokinetics", "https://link.springer.com/article/10.2165/00003088-198713050-00001"),
                                ("CDC Alcohol Facts", "https://www.cdc.gov/alcohol/fact-sheets/alcohol-use.htm"),
                            ]
                        )

                        LearnCard(
                            icon: "atom",
                            iconColor: Color(hex: "#4A9EFF"),
                            title: "The math, in detail",
                            bodyText: "When you log a drink, you're telling SipTrack the moment you STARTED drinking it — not when you finished. SipTrack accounts for this by modelling each drink as a continuous infusion of ethanol into your stomach over a typical drinking duration T (20 min for a beer, 30 min for wine, 1 min for a shot, 25 min for a cocktail). If you log your next drink before T is up, the previous one is auto-truncated.\n\nFor each drink, the absorbed fraction at time Δt after you started:\n\nWhile still drinking (Δt < T):\nabsorbed(Δt) = Δt/T − (1 − e^(−kA·Δt)) / (kA·T)\n\nAfter finishing (Δt ≥ T):\nabsorbed(Δt) = 1 − (1 − e^(−kA·T))/(kA·T) · e^(−kA·(Δt − T))\n\nThe rest of the per-drink contribution:\n\nA = volume × (ABV / 100) × 0.789 g/mL\nfpm = stomach FPM × sex multiplier\nraw(Δt) = (A · (1 − fpm) · absorbed(Δt)) ÷ (W · r · 10)\ncontribution(Δt) = max(0, raw(Δt) − β · Δt)\n\nTotal BAC = sum of every drink's contribution.\n\nParameters used:\n\n• r: Watson 1980 TBW formula → r = TBW / (W × 0.806), clamped to [0.50, 0.85]. Falls back to Forrest BMI fit, then to Widmark constants if profile data is incomplete.\n• β: 0.0138 (men), 0.0157 (women), 0.0148 (neutral) BAC%/h. −5% per decade after age 60.\n• kA: 6.0/h empty stomach, 3.0/h snack, 1.5/h full meal. Linear decay back to empty over 150 min.\n• FPM: 0% empty, 10% snack, 20% full meal; ×0.75 for women.\n• T (drinking duration): per drink type — beer 20 min, wine 30 min, shots 1 min, cocktails 25 min. Multiplied by quantity if you log more than one. Auto-truncated to the gap before your next drink.\n• Standard drink: 14 g pure alcohol (US NIAAA).\n\nFPM is capped at 40% to prevent unrealistic values. The continuous-infusion form correctly reduces to the textbook bolus (1 − e^(−kA·Δt)) when T → 0 — i.e., for a shot.\n\nThe complete research summary, including model alternatives we considered and discarded, lives in the project repo at .planning/research/BAC-ACCURACY-RESEARCH.md.",
                            sources: [
                                ("Watson 1980 TBW", "https://www.msdmanuals.com/professional/multimedia/clinical-calculator/total-body-water-in-men-watson-formula"),
                                ("Forrest 1986", "https://pmc.ncbi.nlm.nih.gov/articles/PMC4361698/"),
                                ("UK Forensic Guidelines", "https://www.ukiaft.org/wp-content/uploads/ukiaft-atd-v4.4.pdf"),
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
