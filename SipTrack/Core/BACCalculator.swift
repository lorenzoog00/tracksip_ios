import Foundation

enum BACStatus { case green, amber, red }

struct BACDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let bac: Double
}

struct BACCalculator {

    // MARK: - Widmark r factor

    static func widmarkR(sex: Sex) -> Double {
        switch sex {
        case .male:           return 0.68
        case .female:         return 0.55
        case .preferNotToSay: return 0.615
        }
    }

    // MARK: - Watson (1980) Total Body Water

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
        let tbw = watsonTBW(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
        return max(0.3, min(0.9, tbw / weightKg))
    }

    static func profileR(profile: UserProfile) -> Double {
        if let h = profile.heightCm, let year = profile.birthYear {
            let age = Calendar.current.component(.year, from: Date()) - year
            return watsonR(weightKg: profile.weightKg, heightCm: h, age: age, sex: profile.sex)
        }
        return widmarkR(sex: profile.sex)
    }

    // MARK: - Core BAC estimation

    static func estimateBAC(
        alcoholGrams: Double,
        weightKg: Double,
        sex: Sex,
        durationHours: Double,
        r: Double? = nil
    ) -> Double {
        let rFactor = r ?? widmarkR(sex: sex)
        let bac = (alcoholGrams / (weightKg * 1000 * rFactor)) * 100
        let metabolized = 0.015 * durationHours
        return max(0, bac - metabolized)
    }

    // Per-drink BAC at a given moment: each drink metabolizes from when it was consumed.
    private static func bacAt(
        _ time: Date,
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        weightKg: Double,
        r: Double
    ) -> Double {
        entries.filter { $0.timestamp <= time }.reduce(0.0) { sum, entry in
            let dt = drinkTypes.first { $0.id == entry.drinkTypeId }
            let vol = entry.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = entry.abvOverride ?? dt?.defaultAbv ?? 0
            let alcohol = calculateAlcohol(volumeMl: vol, abv: abv, quantity: entry.quantity)
            let hours = time.timeIntervalSince(entry.timestamp) / 3600
            let raw = (alcohol / (weightKg * 1000 * r)) * 100
            return sum + max(0, raw - 0.015 * hours)
        }
    }

    static func estimatePeakBAC(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        weightKg: Double,
        sex: Sex,
        eventStart: Date,
        r: Double? = nil
    ) -> Double {
        guard !entries.isEmpty else { return 0 }
        let rFactor = r ?? widmarkR(sex: sex)
        let lastTimestamp = entries.map(\.timestamp).max() ?? eventStart
        let endCheck = lastTimestamp.addingTimeInterval(3600)
        var peak = 0.0
        var checkpoint = eventStart
        while checkpoint <= endCheck {
            peak = max(peak, bacAt(checkpoint, entries: entries, drinkTypes: drinkTypes, weightKg: weightKg, r: rFactor))
            checkpoint = checkpoint.addingTimeInterval(300)
        }
        return peak
    }

    static func bacTimeline(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        profile: UserProfile,
        eventStart: Date
    ) -> [BACDataPoint] {
        guard !entries.isEmpty else { return [] }
        let r = profileR(profile: profile)
        let totalAlcohol = entries.reduce(0.0) { sum, entry in
            let dt = drinkTypes.first { $0.id == entry.drinkTypeId }
            let vol = entry.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = entry.abvOverride ?? dt?.defaultAbv ?? 0
            return sum + calculateAlcohol(volumeMl: vol, abv: abv, quantity: entry.quantity)
        }
        let rawBAC = (totalAlcohol / (profile.weightKg * 1000 * r)) * 100
        let hoursToZero = rawBAC / 0.015
        let endDate = eventStart.addingTimeInterval((hoursToZero + 0.5) * 3600)
        let lastDrink = entries.map(\.timestamp).max() ?? eventStart

        var points: [BACDataPoint] = []
        var checkpoint = eventStart
        while checkpoint <= endDate {
            let bac = bacAt(checkpoint, entries: entries, drinkTypes: drinkTypes, weightKg: profile.weightKg, r: r)
            points.append(BACDataPoint(date: checkpoint, bac: bac))
            if bac == 0 && checkpoint > lastDrink { break }
            checkpoint = checkpoint.addingTimeInterval(300)
        }
        return points
    }

    // MARK: - Mean BAC

    // Mean BAC = average of BAC sampled across [eventStart, eventEnd].
    // Interval scales with duration so short events still get ~20 samples.
    static func meanBACForEvent(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        profile: UserProfile,
        eventStart: Date,
        eventEnd: Date
    ) -> Double {
        guard !entries.isEmpty, eventEnd > eventStart else { return 0 }
        let r = profileR(profile: profile)
        let duration = eventEnd.timeIntervalSince(eventStart)
        let interval = max(1.0, min(300.0, duration / 20.0))
        var sum = 0.0
        var count = 0
        var t = eventStart
        while t <= eventEnd {
            sum += bacAt(t, entries: entries, drinkTypes: drinkTypes, weightKg: profile.weightKg, r: r)
            count += 1
            t = t.addingTimeInterval(interval)
        }
        return count > 0 ? sum / Double(count) : 0
    }

    // MARK: - Alcohol content

    static func calculateAlcohol(volumeMl: Double, abv: Double, quantity: Int) -> Double {
        volumeMl * (abv / 100) * Double(quantity) * 0.789
    }

    static func standardDrinks(alcoholGrams: Double) -> Double {
        alcoholGrams / 14.0
    }

    // MARK: - Time / Status helpers

    static func hoursToZeroBAC(_ bac: Double) -> Double {
        bac / 0.015
    }

    static func getBACStatus(bac: Double, limit: Double) -> BACStatus {
        if bac >= limit { return .red }
        if bac >= limit * 0.8 { return .amber }
        return .green
    }

    // MARK: - Hydration

    static func computeHydrationRatio(waterEntries: [WaterEntry], drinkCount: Int) -> Double {
        guard drinkCount > 0 else { return 0 }
        let glasses = waterEntries.reduce(0.0) { $0 + $1.volumeMl } / 250.0
        return glasses / Double(drinkCount)
    }

    static func applyHydration(bac: Double, ratio: Double) -> Double {
        guard ratio >= 1.25 else { return bac }
        return bac * 0.95
    }

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
        eventStart: Date
    ) -> Double {
        let r = profileR(profile: profile)
        let rawBAC = bacAt(Date(), entries: entries, drinkTypes: drinkTypes, weightKg: profile.weightKg, r: r)
        let ratio = computeHydrationRatio(waterEntries: waterEntries, drinkCount: entries.count)
        return applyHydration(bac: rawBAC, ratio: ratio)
    }

    static func drinksInLastHour(entries: [DrinkEntry]) -> Int {
        let cutoff = Date().addingTimeInterval(-3600)
        return entries.filter { $0.timestamp >= cutoff }.count
    }
}
