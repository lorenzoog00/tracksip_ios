import Foundation

enum BACStatus { case green, amber, red }

struct BACDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let bac: Double
}

// BAC model for SipTrack.
//
// Architecture: Widmark distribution + Watson/Forrest individualisation of `r`,
// first-order gut absorption with food-dependent rate constant `kA`,
// gender-corrected first-pass metabolism, sex-specific elimination β. Multi-
// dose intake is modeled as parallel first-order inputs summed in plasma —
// the standard PBPK approach (Plawecki 2008; Ramchandani group). Each drink
// owns its own absorption curve with `T` = effective drinking duration.
//
// "Gulp detection" (rapid-pace deviation): when a follow-up drink arrives
// inside the previous drink's expected drinking time, the previous drink is
// treated as **instantly fully absorbed Widmark** instead of first-order. This
// is a deliberate UX choice — pharmacologically the correct response would be
// to shrink T toward zero (Mitchell 2014 shows Tmax 36 min spirits → 62 min
// beer, Norberg/Sjögren find 77% of social drinkers absorb in <60 min), but
// users intuit BAC as "alcohol I drank = BAC I have" and read the slow first-
// order curve as a broken meter. Documented in detail in
// .planning/research/BAC-ACCURACY-RESEARCH.md §9.
//
// Numbers traced to: Searle 2015 (PMC4361698), JAAPL 2017, Jones 1996 / 2010,
// Frezza NEJM 1990, Bissinger 2020 (PMC7518982), Maskell 2022, Norberg 2003,
// Mitchell 2014 (acer.12355), Sjögren 1996, Plawecki 2008.
// See LearnView (in-app) and .planning/research/BAC-ACCURACY-RESEARCH.md.

struct BACCalculator {

    // MARK: - Model constants

    private static let ethanolDensityGPerMl = 0.789
    private static let standardDrinkGrams   = 14.0   // US NIAAA

    // Sex-specific elimination β in BAC %/hour (g/100mL/h).
    // Forensic mean 0.0155 ± 0.0029 (JAAPL 2017); split per Bissinger 2020.
    private static let betaMale    = 0.0138
    private static let betaFemale  = 0.0157
    private static let betaNeutral = 0.0148

    // Blood water fraction used to convert TBW → distribution factor r (Searle 2015).
    private static let bloodWaterFraction = 0.806

    // First-order absorption rate constant (1/hour) and first-pass metabolism fraction
    // by stomach state. kA half-life = ln(2)/kA · 60 minutes.
    // Sources: Jones 1996 (FPM), Jones 2010 (kA ranges), Frezza NEJM 1990.
    private struct StomachKinetics {
        let kAPerHour: Double
        let firstPassFraction: Double
    }
    private static func kinetics(for state: StomachState) -> StomachKinetics {
        switch state {
        case .empty:    return .init(kAPerHour: 6.0, firstPassFraction: 0.00) // t½ ≈ 7 min
        case .snack:    return .init(kAPerHour: 3.0, firstPassFraction: 0.10) // t½ ≈ 14 min
        case .fullMeal: return .init(kAPerHour: 1.5, firstPassFraction: 0.20) // t½ ≈ 28 min
        }
    }

    // Time over which a meal's effect on gastric emptying linearly decays back to empty.
    private static let stomachDecayMinutes = 150.0

    // Population coefficient of variation for combined Widmark output (Searle 2015).
    private static let bacCV = 0.20

    // MARK: - Elimination rate β

    static func eliminationRate(sex: Sex) -> Double {
        switch sex {
        case .male:           return betaMale
        case .female:         return betaFemale
        case .preferNotToSay: return betaNeutral
        }
    }

    static func eliminationRate(profile: UserProfile) -> Double {
        var beta = eliminationRate(sex: profile.sex)
        // Age modifier: β slows ~5% per decade after 60 (Vestal 1977; Forensic Sci Int 2014).
        if let age = profile.age, age > 60 {
            let decades = Double(age - 60) / 10.0
            beta *= max(0.75, 1.0 - 0.05 * decades)
        }
        return beta
    }

    // MARK: - Widmark distribution factor r

    static func widmarkR(sex: Sex) -> Double {
        switch sex {
        case .male:           return 0.68
        case .female:         return 0.55
        case .preferNotToSay: return 0.615
        }
    }

    // Watson 1980 total body water (litres).
    static func watsonTBW(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        switch sex {
        case .female:
            return -2.097 + 0.1069 * heightCm + 0.2466 * weightKg
        case .male:
            return 2.447 - 0.09516 * Double(age) + 0.1074 * heightCm + 0.3362 * weightKg
        case .preferNotToSay:
            let f = -2.097 + 0.1069 * heightCm + 0.2466 * weightKg
            let m = 2.447 - 0.09516 * Double(age) + 0.1074 * heightCm + 0.3362 * weightKg
            return (f + m) / 2
        }
    }

    static func watsonR(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        guard weightKg > 0 else { return widmarkR(sex: sex) }
        let tbw = watsonTBW(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
        // r = TBW / (weight · blood-water-fraction). Maskell 2022 recommends TBW form.
        return max(0.50, min(0.85, tbw / (weightKg * bloodWaterFraction)))
    }

    // Forrest/Barbour BMI-based fallback when age is unknown. Linear fits to the
    // Forrest table reproduced in Searle 2015.
    static func forrestR(weightKg: Double, heightCm: Double, sex: Sex) -> Double {
        let hM = heightCm / 100
        guard hM > 0, weightKg > 0 else { return widmarkR(sex: sex) }
        let bmi = weightKg / (hM * hM)
        let r: Double
        switch sex {
        case .male:           r = 0.9215 - 0.00939 * bmi
        case .female:         r = 0.9362 - 0.01225 * bmi
        case .preferNotToSay: r = ((0.9215 - 0.00939 * bmi) + (0.9362 - 0.01225 * bmi)) / 2
        }
        return max(0.50, min(0.85, r))
    }

    static func profileR(profile: UserProfile) -> Double {
        if let h = profile.heightCm, h > 0 {
            if let age = profile.age, age > 0 {
                return watsonR(weightKg: profile.weightKg, heightCm: h, age: age, sex: profile.sex)
            }
            return forrestR(weightKg: profile.weightKg, heightCm: h, sex: profile.sex)
        }
        return widmarkR(sex: profile.sex)
    }

    // MARK: - Closed-form estimate (legacy API)

    // Single-shot Widmark estimate. Kept for callers that don't have per-drink data.
    static func estimateBAC(
        alcoholGrams: Double,
        weightKg: Double,
        sex: Sex,
        durationHours: Double,
        r: Double? = nil
    ) -> Double {
        guard weightKg > 0 else { return 0 }
        let rFactor = r ?? widmarkR(sex: sex)
        let bac = (alcoholGrams / (weightKg * 1000 * rFactor)) * 100
        return max(0, bac - eliminationRate(sex: sex) * durationHours)
    }

    // MARK: - Per-drink first-order absorption model

    // Fraction of a drink's dose that has been absorbed into the bloodstream Δt hours
    // after the user STARTED drinking it. Models a continuous infusion into the gut
    // over duration `T` (the drinking duration) followed by first-order gastric
    // emptying at rate `kA`. Reduces to the bolus form `1 − e^(−kA·Δt)` as T → 0.
    private static func absorbedFraction(deltaHours: Double, kA: Double, durationHours T: Double) -> Double {
        guard deltaHours > 0, kA > 0 else { return 0 }
        // Below ~1 second of duration: indistinguishable from a bolus.
        if T < 1.0 / 3600.0 { return 1.0 - exp(-kA * deltaHours) }
        let kT = kA * T
        if deltaHours < T {
            // Still drinking — linear input minus what's still in the gut.
            return max(0, deltaHours / T - (1.0 - exp(-kA * deltaHours)) / kT)
        }
        // Done drinking — residual gut empties exponentially.
        let residualAtFinish = (1.0 - exp(-kT)) / kT
        return 1.0 - residualAtFinish * exp(-kA * (deltaHours - T))
    }

    private static func bacAt(
        _ time: Date,
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        weightKg: Double,
        r: Double,
        beta: Double,
        sex: Sex,
        stomachState: StomachState,
        stomachStateTimestamp: Date,
        foodEntries: [FoodEntry]
    ) -> Double {
        guard weightKg > 0, r > 0 else { return 0 }
        // Female gastric ADH activity ≈ 25% lower than male → less first-pass metabolism
        // → higher peak BAC for same dose. (Frezza NEJM 1990.)
        let fpmSexMultiplier: Double
        switch sex {
        case .female:         fpmSexMultiplier = 0.75
        case .preferNotToSay: fpmSexMultiplier = 0.875
        case .male:           fpmSexMultiplier = 1.0
        }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var sum = 0.0
        for i in sorted.indices {
            let entry = sorted[i]
            let dt    = drinkTypes.first { $0.id == entry.drinkTypeId }
            let vol   = entry.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv   = entry.abvOverride ?? dt?.defaultAbv ?? 0
            let dose  = calculateAlcohol(volumeMl: vol, abv: abv, quantity: entry.quantity)
            guard dose > 0, time >= entry.timestamp else { continue }

            let factor = computeStomachFactor(
                at: entry.timestamp,
                stomachState: stomachState,
                stomachStateTimestamp: stomachStateTimestamp,
                foodEntries: foodEntries
            )
            let fpm = min(0.40, factor.firstPassFraction * fpmSexMultiplier)

            // Effective drinking duration in hours. Scales with quantity (3 beers = 3×
            // the typical time). If the next drink starts before this one's typical
            // drinking time elapses, the user gulped this drink: we treat the full
            // dose as already absorbed at the entry timestamp (instant Widmark) so
            // the live BAC visibly spikes the moment a fast-paced drink is logged.
            //
            // PK background: gulping accelerates Cmax and shortens Tmax but does
            // not bypass gut absorption — Mitchell 2014 (acer.12355) measured Tmax
            // 36 ± 10 min for vodka, 54 ± 14 min wine, 62 ± 23 min beer at 0.5 g/kg
            // over 20 min on an empty stomach; Sjögren 1996 found 77% of social
            // drinkers complete absorption within 60 min. A pharmacologically
            // correct implementation collapses T → 0 and lets the first-order
            // curve with kA from `kinetics(for:)` run (Jones 2010; Norberg 2003;
            // Plawecki 2008 PBPK). We deliberately deviate: users read the slow
            // first-order rise as "the calculator isn't reacting" and lose trust.
            // Setting `absorbed = 1.0` makes the gulped drink's contribution land
            // in plasma at its timestamp, matching the intuitive model and the
            // bolus assumption used by classic Widmark forensic estimation.
            // See .planning/research/BAC-ACCURACY-RESEARCH.md §9 for the full
            // rationale and the alternatives considered.
            let perServing = Double(dt?.effectiveDrinkingMinutes ?? 15)
            var T = perServing * Double(max(1, entry.quantity)) / 60.0
            var gulped = false
            if i + 1 < sorted.count {
                let gap = sorted[i + 1].timestamp.timeIntervalSince(entry.timestamp) / 3600
                if gap >= 0, gap < T {
                    T = 0
                    gulped = true
                }
            }

            let hours    = time.timeIntervalSince(entry.timestamp) / 3600
            let absorbed = gulped ? 1.0
                                  : absorbedFraction(deltaHours: hours, kA: factor.kAPerHour, durationHours: T)
            let aEff     = dose * (1.0 - fpm) * absorbed
            let raw      = (aEff / (weightKg * 1000 * r)) * 100
            sum += max(0, raw - beta * hours)
        }
        return sum
    }

    static func estimatePeakBAC(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        weightKg: Double,
        sex: Sex,
        eventStart: Date,
        r: Double? = nil,
        stomachState: StomachState = .empty,
        stomachStateTimestamp: Date? = nil,
        foodEntries: [FoodEntry] = []
    ) -> Double {
        guard !entries.isEmpty else { return 0 }
        let rFactor     = r ?? widmarkR(sex: sex)
        let beta        = eliminationRate(sex: sex)
        let stTimestamp = stomachStateTimestamp ?? eventStart
        let lastTimestamp = entries.map(\.timestamp).max() ?? eventStart
        // Peak typically within 60–120 min after last drink even with food. Scan to +2 h.
        let endCheck    = lastTimestamp.addingTimeInterval(7200)
        var peak        = 0.0
        var checkpoint  = eventStart
        while checkpoint <= endCheck {
            let bac = bacAt(
                checkpoint,
                entries: entries, drinkTypes: drinkTypes,
                weightKg: weightKg, r: rFactor, beta: beta, sex: sex,
                stomachState: stomachState, stomachStateTimestamp: stTimestamp,
                foodEntries: foodEntries
            )
            peak = max(peak, bac)
            checkpoint = checkpoint.addingTimeInterval(300)
        }
        return peak
    }

    static func bacTimeline(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        profile: UserProfile,
        eventStart: Date,
        stomachState: StomachState = .empty,
        stomachStateTimestamp: Date? = nil,
        foodEntries: [FoodEntry] = []
    ) -> [BACDataPoint] {
        guard !entries.isEmpty, profile.weightKg > 0 else { return [] }
        let r           = profileR(profile: profile)
        let beta        = eliminationRate(profile: profile)
        let stTimestamp = stomachStateTimestamp ?? eventStart
        let totalAlcohol = entries.reduce(0.0) { sum, entry in
            let dt  = drinkTypes.first { $0.id == entry.drinkTypeId }
            let vol = entry.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = entry.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + calculateAlcohol(volumeMl: vol, abv: abv, quantity: entry.quantity)
        }
        guard totalAlcohol > 0 else { return [] }
        let rawBAC      = (totalAlcohol / (profile.weightKg * 1000 * r)) * 100
        let hoursToZero = rawBAC / beta
        let endDate     = eventStart.addingTimeInterval((hoursToZero + 1.5) * 3600)
        let lastDrink   = entries.map(\.timestamp).max() ?? eventStart

        var points: [BACDataPoint] = []
        var checkpoint = eventStart
        while checkpoint <= endDate {
            let bac = bacAt(
                checkpoint,
                entries: entries, drinkTypes: drinkTypes,
                weightKg: profile.weightKg, r: r, beta: beta, sex: profile.sex,
                stomachState: stomachState, stomachStateTimestamp: stTimestamp,
                foodEntries: foodEntries
            )
            points.append(BACDataPoint(date: checkpoint, bac: bac))
            if bac == 0 && checkpoint > lastDrink { break }
            checkpoint = checkpoint.addingTimeInterval(300)
        }
        return points
    }

    // MARK: - Mean BAC

    static func meanBACForEvent(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        profile: UserProfile,
        eventStart: Date,
        eventEnd: Date,
        stomachState: StomachState = .empty,
        stomachStateTimestamp: Date? = nil,
        foodEntries: [FoodEntry] = []
    ) -> Double {
        guard !entries.isEmpty, eventEnd > eventStart else { return 0 }
        let r           = profileR(profile: profile)
        let beta        = eliminationRate(profile: profile)
        let stTimestamp = stomachStateTimestamp ?? eventStart
        let duration = eventEnd.timeIntervalSince(eventStart)
        let interval = max(1.0, min(300.0, duration / 20.0))
        var sum = 0.0
        var count = 0
        var t = eventStart
        while t <= eventEnd {
            sum += bacAt(
                t,
                entries: entries, drinkTypes: drinkTypes,
                weightKg: profile.weightKg, r: r, beta: beta, sex: profile.sex,
                stomachState: stomachState, stomachStateTimestamp: stTimestamp,
                foodEntries: foodEntries
            )
            count += 1
            t = t.addingTimeInterval(interval)
        }
        return count > 0 ? sum / Double(count) : 0
    }

    // MARK: - Uncertainty band (population CV ≈ 20% per Searle 2015)

    static func uncertaintyBand(point: Double) -> (low: Double, high: Double) {
        guard point > 0 else { return (0, 0) }
        return (max(0, point * (1 - bacCV)), point * (1 + bacCV))
    }

    // MARK: - Alcohol content

    static func calculateAlcohol(volumeMl: Double, abv: Double, quantity: Int) -> Double {
        volumeMl * (abv / 100) * Double(quantity) * ethanolDensityGPerMl
    }

    static func standardDrinks(alcoholGrams: Double) -> Double {
        alcoholGrams / standardDrinkGrams
    }

    // MARK: - Time / Status helpers

    static func hoursToZeroBAC(_ bac: Double, sex: Sex = .preferNotToSay) -> Double {
        bac / eliminationRate(sex: sex)
    }

    static func hoursToZeroBAC(_ bac: Double, profile: UserProfile) -> Double {
        bac / eliminationRate(profile: profile)
    }

    static func getBACStatus(bac: Double, limit: Double) -> BACStatus {
        if bac >= limit { return .red }
        if bac >= limit * 0.8 { return .amber }
        return .green
    }

    // MARK: - Hydration (UI/coaching only — does NOT modify BAC)

    static func computeHydrationRatio(waterEntries: [WaterEntry], drinkCount: Int) -> Double {
        guard drinkCount > 0 else { return 0 }
        let glasses = waterEntries.reduce(0.0) { $0 + $1.volumeMl } / 250.0
        return glasses / Double(drinkCount)
    }

    // Water intake does not pharmacokinetically lower BAC. The pharmacology literature
    // is consistent on this. Function retained for API compatibility; returns input.
    static func applyHydration(bac: Double, ratio: Double) -> Double { bac }

    enum HydrationLevel: String {
        case none = "none", behind = "behind", balanced = "balanced", great = "great"
    }

    static func hydrationLevel(waterEntries: [WaterEntry], drinkCount: Int) -> HydrationLevel {
        guard drinkCount > 0 else { return .none }
        let ratio = computeHydrationRatio(waterEntries: waterEntries, drinkCount: drinkCount)
        if ratio <= 0 { return .none }
        if ratio < 0.85 { return .behind }
        if ratio < 1.25 { return .balanced }
        return .great
    }

    // MARK: - Live BAC for active event

    static func currentBAC(
        entries: [DrinkEntry],
        waterEntries: [WaterEntry],
        drinkTypes: [DrinkType],
        profile: UserProfile,
        eventStart: Date,
        stomachState: StomachState = .empty,
        stomachStateTimestamp: Date? = nil,
        foodEntries: [FoodEntry] = []
    ) -> Double {
        let r           = profileR(profile: profile)
        let beta        = eliminationRate(profile: profile)
        let stTimestamp = stomachStateTimestamp ?? eventStart
        return bacAt(
            Date(),
            entries: entries, drinkTypes: drinkTypes,
            weightKg: profile.weightKg, r: r, beta: beta, sex: profile.sex,
            stomachState: stomachState, stomachStateTimestamp: stTimestamp,
            foodEntries: foodEntries
        )
    }

    static func drinksInLastHour(entries: [DrinkEntry]) -> Int {
        let cutoff = Date().addingTimeInterval(-3600)
        return entries.filter { $0.timestamp >= cutoff }.count
    }

    // MARK: - Stomach / food factor

    // Returns (kA, FPM) at a drink moment. Effects from the user's declared start-of-night
    // stomach state and each logged food entry both decay linearly toward empty over
    // `stomachDecayMinutes`. The slowest absorption / highest FPM still in effect wins.
    static func computeStomachFactor(
        at drinkTime: Date,
        stomachState: StomachState,
        stomachStateTimestamp: Date,
        foodEntries: [FoodEntry]
    ) -> (kAPerHour: Double, firstPassFraction: Double) {

        let empty = kinetics(for: .empty)

        func resolved(state: StomachState, since: Date) -> (kA: Double, fpm: Double) {
            let minutes = max(0, drinkTime.timeIntervalSince(since) / 60)
            let weight  = max(0.0, 1.0 - minutes / stomachDecayMinutes)
            let k       = kinetics(for: state)
            let kA  = empty.kAPerHour         * (1 - weight) + k.kAPerHour         * weight
            let fpm = empty.firstPassFraction * (1 - weight) + k.firstPassFraction * weight
            return (kA, fpm)
        }

        var best = resolved(state: stomachState, since: stomachStateTimestamp)
        for entry in foodEntries where entry.timestamp <= drinkTime {
            let r = resolved(state: entry.type, since: entry.timestamp)
            if r.kA < best.kA  { best.kA  = r.kA }
            if r.fpm > best.fpm { best.fpm = r.fpm }
        }
        return (kAPerHour: best.kA, firstPassFraction: best.fpm)
    }
}
