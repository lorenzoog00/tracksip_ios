# BAC Model Core Accuracy — Implementation Plan (1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace zero-order closed-form elimination with a forward-integrated one-compartment model using Michaelis–Menten elimination (calibrated `Vmax`) and concentration-dependent absorption `kA(%ABV)`, so the BAC curve's peak timing, peak height, and descending tail match the published pharmacokinetics — without changing any public `BACCalculator` signature.

**Architecture:** `BACCalculator` gains a private `integrateBAC(...)` that marches the BAC ODE forward in 1-minute steps: each step adds newly-absorbed alcohol (per-drink first-order absorption over the drinking duration `T`, gulp = instant) and subtracts Michaelis–Menten elimination on the *current* blood level. All existing public functions (`bacAt`, `bacTimeline`, `estimatePeakBAC`, `meanBACForEvent`, `currentBAC`) are rewired to call it; their signatures and call-sites stay identical. New pure helpers (`absorptionRateEmpty(abv:)`, `vmax(beta:)`) are independently unit-tested. The science is validated against Mitchell 2014 Cmax/Tmax fixtures and against the old zero-order curve in the 0.05–0.10 regime.

**Tech Stack:** Swift, Swift `Testing` framework (`@Test` / `#expect`), Xcode. Spec: `docs/superpowers/specs/2026-06-06-bac-accuracy-overhaul-design.md`.

---

## File Structure

- **Modify:** `SipTrack/Core/BACCalculator.swift` — add constants + 2 helpers; add private `integrateBAC`; rewire `bacAt`/`bacTimeline`/`estimatePeakBAC`/`meanBACForEvent`. No public signature changes.
- **Test:** `siptrackTests/BACCalculatorCoreTests.swift` — keep all existing tests green; add helper tests.
- **Create:** `siptrackTests/BACCalculatorKineticsTests.swift` — M-M tail, Mitchell Tmax/Cmax fixtures, gulp-preserved, regression vs zero-order.

> **Build/test command (macOS host required):**
> `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:siptrackTests/<Suite>`
> If a simulator name differs, run `xcrun simctl list devices available` and substitute. On a Windows dev box without Xcode, these steps must run on the macOS build machine.

---

## Task 1: Kinetics constants + pure helpers

**Files:**
- Modify: `SipTrack/Core/BACCalculator.swift` (constants block near line 37–70; add helpers in a new `MARK: - Kinetics` section)
- Test: `siptrackTests/BACCalculatorKineticsTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

Create `siptrackTests/BACCalculatorKineticsTests.swift`:

```swift
import Testing
@testable import siptrack

struct BACCalculatorKineticsTests {

    // MARK: - Vmax calibration

    @Test func vmax_isAboveBeta_andReproducesBetaAtReference() {
        let beta = 0.0138
        let vmax = BACCalculator.vmax(beta: beta)
        // Vmax must exceed the observed slope...
        #expect(vmax > beta)
        // ...and the M-M rate at the 0.08 reference must equal beta.
        let km = BACCalculator.michaelisKm
        let rateAtRef = vmax * 0.08 / (km + 0.08)
        #expect(abs(rateAtRef - beta) < 1e-6)
    }

    // MARK: - absorptionRateEmpty(abv:)

    @Test func absorptionRate_peaksNearTwentyPercent() {
        let beer    = BACCalculator.absorptionRateEmpty(abv: 5)
        let wine     = BACCalculator.absorptionRateEmpty(abv: 12.5)
        let mixed20  = BACCalculator.absorptionRateEmpty(abv: 20)
        let neat40   = BACCalculator.absorptionRateEmpty(abv: 40)
        // Fastest near ~20% v/v; dilute and very strong are slower.
        #expect(mixed20 > wine)
        #expect(wine > beer)
        #expect(mixed20 > neat40)
        #expect(beer > 0)
    }

    @Test func absorptionRate_clampsAtExtremes() {
        #expect(BACCalculator.absorptionRateEmpty(abv: 0) > 0)
        #expect(BACCalculator.absorptionRateEmpty(abv: 100) > 0)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorKineticsTests`
Expected: FAIL — `vmax`, `michaelisKm`, `absorptionRateEmpty` are undefined.

- [ ] **Step 3: Add constants + helpers**

In `BACCalculator.swift`, add to the constants block (after `bacCV`):

```swift
    // MARK: - Michaelis–Menten elimination constants

    // Michaelis constant: BAC at which elimination runs at half Vmax. Human curve-fit
    // midpoint (Toxics 2023 0.02 g/L; pop-PK 0.038 g/L; Vestal in-vitro 0.06 g/L).
    static let michaelisKm = 0.004   // g/100mL (0.04 g/L)

    // BAC at which the published zero-order β was empirically measured (descending limb).
    private static let betaRefBAC = 0.08  // g/100mL

    // 1-minute integration step for the forward ODE solver.
    private static let integrationStepHours = 1.0 / 60.0
```

Add a new section (e.g. after `computeStomachFactor`):

```swift
    // MARK: - Kinetics helpers

    // The published β is the *observed* descending-limb slope at C ≈ betaRefBAC, not the
    // true Vmax. Back-calibrate Vmax so the M-M rate equals β at that reference, then
    // M-M only bends slower below ~0.02 (the evidence-based tail correction).
    static func vmax(beta: Double) -> Double {
        beta * (michaelisKm + betaRefBAC) / betaRefBAC
    }

    // Empty-stomach gut absorption constant (1/h) as a function of beverage strength.
    // Gastric emptying is rate-limiting and fastest near ~20% v/v; dilute (beer) and very
    // strong (neat spirits) empty slower. Anchors calibrated so the integrated model
    // reproduces Mitchell 2014 Tmax at 0.5 g/kg (see BACCalculatorKineticsTests).
    static func absorptionRateEmpty(abv: Double) -> Double {
        let anchors: [(abv: Double, kA: Double)] = [
            (0, 1.5), (5, 3.5), (12.5, 4.3), (20, 10.0), (40, 6.0), (100, 4.0)
        ]
        if abv <= anchors.first!.abv { return anchors.first!.kA }
        if abv >= anchors.last!.abv  { return anchors.last!.kA }
        for i in 1..<anchors.count where abv <= anchors[i].abv {
            let lo = anchors[i - 1], hi = anchors[i]
            let t = (abv - lo.abv) / (hi.abv - lo.abv)
            return lo.kA + t * (hi.kA - lo.kA)
        }
        return anchors.last!.kA
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorKineticsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add SipTrack/Core/BACCalculator.swift siptrackTests/BACCalculatorKineticsTests.swift
git commit -m "feat(bac): add M-M constants, Vmax calibration, and kA(ABV) helper"
```

---

## Task 2: Forward-integration core `integrateBAC`

**Files:**
- Modify: `SipTrack/Core/BACCalculator.swift` (add private `integrateBAC`; rewrite `bacAt` body to delegate)
- Test: `siptrackTests/BACCalculatorCoreTests.swift` (existing tests must stay green)

- [ ] **Step 1: Add the private integrator**

Add to `BACCalculator` (new `MARK: - Forward integration`):

```swift
    // Marches the one-compartment BAC ODE forward in 1-minute steps from the first drink
    // to `until` (or until BAC≈0 after the last drink when `until` is nil). Each step adds
    // newly-absorbed alcohol (per-drink first-order absorption over duration T; gulp =
    // instant) and subtracts Michaelis–Menten elimination on the current blood level.
    // Returns samples every `sampleSeconds`. Replaces the closed-form `sum − β·t`.
    private struct PreparedDrink {
        let startHours: Double  // hours after the first drink
        let dose: Double        // grams ethanol
        let fpm: Double         // first-pass fraction removed
        let kA: Double          // absorption constant (1/h), concentration + food adjusted
        let drinkingHours: Double // T (0 if gulped)
        let gulped: Bool
    }

    private static func integrateBAC(
        entries: [DrinkEntry],
        drinkTypes: [DrinkType],
        weightKg: Double,
        r: Double,
        beta: Double,
        sex: Sex,
        stomachState: StomachState,
        stomachStateTimestamp: Date,
        foodEntries: [FoodEntry],
        until: Date?,
        sampleSeconds: TimeInterval = 300
    ) -> [BACDataPoint] {
        guard weightKg > 0, r > 0 else { return [] }
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        guard let firstTs = sorted.first?.timestamp else { return [] }

        let fpmSexMultiplier: Double
        switch sex {
        case .female:         fpmSexMultiplier = 0.75
        case .preferNotToSay: fpmSexMultiplier = 0.875
        case .male:           fpmSexMultiplier = 1.0
        }
        let emptyKA = kinetics(for: .empty).kAPerHour  // 6.0 baseline for food-slowing ratio

        var prepared: [PreparedDrink] = []
        for i in sorted.indices {
            let e   = sorted[i]
            let dt  = drinkTypes.first { $0.id == e.drinkTypeId }
            let vol = e.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
            let abv = e.abvOverride ?? dt?.defaultAbv ?? 0
            let dose = calculateAlcohol(volumeMl: vol, abv: abv, quantity: e.quantity)
            guard dose > 0 else { continue }

            let factor = computeStomachFactor(
                at: e.timestamp, stomachState: stomachState,
                stomachStateTimestamp: stomachStateTimestamp, foodEntries: foodEntries
            )
            let fpm = min(0.40, factor.firstPassFraction * fpmSexMultiplier)
            // Concentration-based empty kA, slowed by food in proportion to the stomach
            // factor (1.0 empty → 0.25 full meal). Preserves food deceleration while
            // making absorption speed depend on beverage strength.
            let foodSlowing = factor.kAPerHour / emptyKA
            let kA = absorptionRateEmpty(abv: abv) * foodSlowing

            let perServing = Double(dt?.effectiveDrinkingMinutes ?? 15)
            var T = perServing * Double(max(1, e.quantity)) / 60.0
            var gulped = false
            if i + 1 < sorted.count {
                let gap = sorted[i + 1].timestamp.timeIntervalSince(e.timestamp) / 3600
                if gap >= 0, gap < T { T = 0; gulped = true }
            }
            prepared.append(PreparedDrink(
                startHours: e.timestamp.timeIntervalSince(firstTs) / 3600,
                dose: dose, fpm: fpm, kA: kA, drinkingHours: T, gulped: gulped
            ))
        }
        guard !prepared.isEmpty else { return [] }

        let vMax = vmax(beta: beta)
        let lastStart = prepared.map(\.startHours).max() ?? 0
        let untilHours = until.map { max(0, $0.timeIntervalSince(firstTs) / 3600) }
        let endHours = untilHours ?? (lastStart + 24)

        func absorbed(_ p: PreparedDrink, since: Double) -> Double {
            guard since > 0 else { return 0 }
            if p.gulped { return 1.0 }
            return absorbedFraction(deltaHours: since, kA: p.kA, durationHours: p.drinkingHours)
        }

        var c = 0.0
        var tH = 0.0
        let sampleH = sampleSeconds / 3600
        var nextSample = 0.0
        var out: [BACDataPoint] = []

        while tH <= endHours + 1e-9 {
            if tH + 1e-9 >= nextSample {
                out.append(BACDataPoint(date: firstTs.addingTimeInterval(tH * 3600), bac: max(0, c)))
                nextSample += sampleH
            }
            if let u = untilHours, tH + 1e-9 >= u { break }

            let tNext = tH + integrationStepHours
            var dCin = 0.0
            for p in prepared {
                let s1 = tNext - p.startHours
                guard s1 > 0 else { continue }
                let dA = max(0, absorbed(p, since: s1) - absorbed(p, since: tH - p.startHours))
                dCin += p.dose * (1 - p.fpm) * dA
            }
            dCin = dCin / (weightKg * 1000 * r) * 100
            let dCout = vMax * c / (michaelisKm + c) * integrationStepHours
            c = max(0, c + dCin - dCout)
            tH = tNext

            if untilHours == nil, tH > lastStart, c <= 0 {
                out.append(BACDataPoint(date: firstTs.addingTimeInterval(tH * 3600), bac: 0))
                break
            }
        }
        return out
    }
```

- [ ] **Step 2: Rewrite `bacAt` to delegate**

Replace the entire body of the existing private `bacAt(...)` (keep its signature) with:

```swift
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
        let points = integrateBAC(
            entries: entries, drinkTypes: drinkTypes, weightKg: weightKg, r: r,
            beta: beta, sex: sex, stomachState: stomachState,
            stomachStateTimestamp: stomachStateTimestamp, foodEntries: foodEntries,
            until: time, sampleSeconds: 60
        )
        return points.last?.bac ?? 0
    }
```

- [ ] **Step 3: Run the existing core suite**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorCoreTests`
Expected: PASS — all existing tests, including `currentBAC_noEntries_returnsZero`, `currentBAC_drinkLongAgo_approachesZero`, `bacTimeline_peakIsPositive`. (`currentBAC`/`bacTimeline` already route through `bacAt`.)

- [ ] **Step 4: If `currentBAC_drinkLongAgo_approachesZero` fails**

It asserts exactly `0` after 10 h for one beer. The M-M tail extends time-to-zero by only ~30–60 min, so 10 h is still 0. If it returns a tiny non-zero due to step accumulation, confirm the early-exit (`c <= 0` after last drink) fired; the `max(0, …)` clamp guarantees 0. Do **not** weaken the test — fix the integrator.

- [ ] **Step 5: Commit**

```bash
git add SipTrack/Core/BACCalculator.swift
git commit -m "feat(bac): forward-integrate BAC via integrateBAC; bacAt delegates"
```

---

## Task 3: Rewire timeline / peak / mean to the integrator

**Files:**
- Modify: `SipTrack/Core/BACCalculator.swift` (`bacTimeline`, `estimatePeakBAC`, `meanBACForEvent`)
- Test: `siptrackTests/BACCalculatorCoreTests.swift` (stay green)

- [ ] **Step 1: Rewrite `bacTimeline` body**

Keep the signature; replace the per-checkpoint loop with one integration pass:

```swift
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
        return integrateBAC(
            entries: entries, drinkTypes: drinkTypes,
            weightKg: profile.weightKg, r: profileR(profile: profile),
            beta: eliminationRate(profile: profile), sex: profile.sex,
            stomachState: stomachState,
            stomachStateTimestamp: stomachStateTimestamp ?? eventStart,
            foodEntries: foodEntries, until: nil, sampleSeconds: 300
        )
    }
```

- [ ] **Step 2: Rewrite `estimatePeakBAC` body**

```swift
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
        let points = integrateBAC(
            entries: entries, drinkTypes: drinkTypes, weightKg: weightKg,
            r: r ?? widmarkR(sex: sex), beta: eliminationRate(sex: sex), sex: sex,
            stomachState: stomachState,
            stomachStateTimestamp: stomachStateTimestamp ?? eventStart,
            foodEntries: foodEntries, until: nil, sampleSeconds: 300
        )
        return points.map(\.bac).max() ?? 0
    }
```

- [ ] **Step 3: Rewrite `meanBACForEvent` body**

```swift
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
        let points = integrateBAC(
            entries: entries, drinkTypes: drinkTypes,
            weightKg: profile.weightKg, r: profileR(profile: profile),
            beta: eliminationRate(profile: profile), sex: profile.sex,
            stomachState: stomachState,
            stomachStateTimestamp: stomachStateTimestamp ?? eventStart,
            foodEntries: foodEntries, until: eventEnd, sampleSeconds: 60
        )
        let inWindow = points.filter { $0.date >= eventStart && $0.date <= eventEnd }
        guard !inWindow.isEmpty else { return 0 }
        return inWindow.reduce(0.0) { $0 + $1.bac } / Double(inWindow.count)
    }
```

- [ ] **Step 4: Run the full existing suite**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorCoreTests`
Expected: PASS (all). `bacTimeline_peakIsPositive` and `bacTimeline_emptyEntries_returnsEmpty` covered.

- [ ] **Step 5: Commit**

```bash
git add SipTrack/Core/BACCalculator.swift
git commit -m "refactor(bac): route timeline/peak/mean through integrateBAC"
```

---

## Task 4: Michaelis–Menten tail behavior tests

**Files:**
- Test: `siptrackTests/BACCalculatorKineticsTests.swift` (append)

- [ ] **Step 1: Write the tail tests**

Append to `BACCalculatorKineticsTests`:

```swift
    private func maleProfile(weight: Double = 80) -> UserProfile {
        var p = UserProfile(); p.weightKg = weight; p.sex = .male; p.birthYear = 1990
        return p
    }

    private func beer(_ id: String, at: Date, qty: Int = 1) -> DrinkEntry {
        DrinkEntry(id: id, eventId: "e", drinkTypeId: "beer", timestamp: at,
                   quantity: qty, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
    }

    @Test func mmTail_extendsTimeToZeroVsLinear() {
        // Compare the integrated tail against a pure linear β extrapolation from the peak.
        let profile = maleProfile()
        let beerType = DrinkType.presets.first { $0.id == "beer" }!
        let start = Date()
        let entries = [beer("d1", at: start, qty: 3)]
        let curve = BACCalculator.bacTimeline(
            entries: entries, drinkTypes: [beerType], profile: profile, eventStart: start
        )
        let peak = curve.map(\.bac).max() ?? 0
        #expect(peak > 0)
        // Time from peak to (near) zero under M-M must exceed the linear estimate peak/β,
        // because elimination slows below ~0.02.
        let beta = BACCalculator.eliminationRate(profile: profile)
        let linearHoursToZero = peak / beta
        guard let peakPoint = curve.max(by: { $0.bac < $1.bac }),
              let zeroPoint  = curve.last(where: { $0.bac > 0 }) else { return }
        let mmHours = zeroPoint.date.timeIntervalSince(peakPoint.date) / 3600
        #expect(mmHours > linearHoursToZero)
    }

    @Test func highBAC_matchesZeroOrderWithinFivePercent() {
        // In the 0.05–0.10 regime M-M ≈ β (Vmax calibrated at 0.08). Spot-check the
        // descending slope over one hour equals β within ±5%.
        let profile = maleProfile()
        let beerType = DrinkType.presets.first { $0.id == "beer" }!
        let start = Date()
        // 6 beers up front to reach ~0.10 then watch the decline.
        let entries = [beer("d1", at: start, qty: 6)]
        let curve = BACCalculator.bacTimeline(
            entries: entries, drinkTypes: [beerType], profile: profile, eventStart: start
        )
        // Find two descending points around 0.08.
        let desc = curve.drop { $0.bac < (curve.map(\.bac).max() ?? 0) }  // from peak onward
        let around = desc.filter { $0.bac <= 0.09 && $0.bac >= 0.06 }
        guard around.count >= 2, let a = around.first, let b = around.dropFirst().first(where: {
            $0.date.timeIntervalSince(a.date) >= 1800 // ≥30 min apart
        }) else { return }
        let slopePerHour = (a.bac - b.bac) / (b.date.timeIntervalSince(a.date) / 3600)
        let beta = BACCalculator.eliminationRate(profile: profile)
        #expect(abs(slopePerHour - beta) / beta < 0.05)
    }
```

- [ ] **Step 2: Run**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorKineticsTests`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add siptrackTests/BACCalculatorKineticsTests.swift
git commit -m "test(bac): M-M tail extends sober-time; high-BAC matches zero-order"
```

---

## Task 5: Mitchell 2014 peak fixtures (kA calibration gate)

**Files:**
- Test: `siptrackTests/BACCalculatorKineticsTests.swift` (append)
- Modify (only if a fixture fails): the `absorptionRateEmpty` anchors from Task 1.

- [ ] **Step 1: Write the fixture tests**

These reproduce Mitchell 2014: 0.5 g/kg (= 40 g for 80 kg), drunk over ~20 min, empty stomach. Build custom drink types at the study concentrations so dose = 40 g and `effectiveDrinkingMinutes = 20`.

```swift
    private func studyDrink(abv: Double, volumeForFortyGrams: Double) -> DrinkType {
        // volume chosen so 40 g ethanol: g = vol·(abv/100)·0.789  ⇒ vol = 40 / (abv/100 · 0.789)
        DrinkType(id: "study-\(Int(abv))", name: "study", defaultVolumeMl: volumeForFortyGrams,
                  defaultAbv: abv, caloriesPerServing: 0, isPreset: false, icon: "flask",
                  defaultDrinkingDurationMinutes: 20)
    }

    private func peakAndTmax(abv: Double) -> (cmax: Double, tmaxMin: Double) {
        let profile = maleProfile(weight: 80)
        let vol = 40.0 / ((abv / 100) * 0.789)
        let type = studyDrink(abv: abv, volumeForFortyGrams: vol)
        let start = Date()
        let entry = DrinkEntry(id: "s", eventId: "e", drinkTypeId: type.id, timestamp: start,
                               quantity: 1, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
        let curve = BACCalculator.bacTimeline(
            entries: [entry], drinkTypes: [type], profile: profile, eventStart: start
        )
        let peak = curve.max(by: { $0.bac < $1.bac })!
        return (peak.bac, peak.date.timeIntervalSince(start) / 60)
    }

    @Test func mitchell_cmaxOrdering_spiritsGtWineGtBeer() {
        let spirits = peakAndTmax(abv: 20).cmax
        let wine    = peakAndTmax(abv: 12.5).cmax
        let beer    = peakAndTmax(abv: 5).cmax
        #expect(spirits > wine)
        #expect(wine > beer)
    }

    @Test func mitchell_cmaxMagnitudes_withinTwentyPercent() {
        // Mitchell mean Cmax: spirits 0.077, wine 0.062, beer 0.050 (g/100mL).
        #expect(abs(peakAndTmax(abv: 20).cmax  - 0.077) / 0.077 < 0.20)
        #expect(abs(peakAndTmax(abv: 12.5).cmax - 0.062) / 0.062 < 0.20)
        #expect(abs(peakAndTmax(abv: 5).cmax   - 0.050) / 0.050 < 0.20)
    }

    @Test func mitchell_tmaxOrdering_andRange() {
        let spirits = peakAndTmax(abv: 20).tmaxMin
        let wine    = peakAndTmax(abv: 12.5).tmaxMin
        let beer    = peakAndTmax(abv: 5).tmaxMin
        // Mitchell: spirits 36, wine 54, beer 60 min. Order strict, each within ±15 min.
        #expect(spirits < wine)
        #expect(wine < beer)
        #expect(abs(spirits - 36) <= 15)
        #expect(abs(wine - 54) <= 15)
        #expect(abs(beer - 60) <= 15)
    }
```

- [ ] **Step 2: Run**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorKineticsTests`
Expected: PASS. **If any `mitchell_*` magnitude/Tmax test fails, the `absorptionRateEmpty` anchors are the calibration knob** — adjust the `kA` anchor values (Task 1, Step 3) and re-run. The orderings should hold regardless; only the magnitudes need tuning. Keep Km/Vmax untouched (validated). Document any anchor change in the commit message.

- [ ] **Step 3: Commit**

```bash
git add siptrackTests/BACCalculatorKineticsTests.swift SipTrack/Core/BACCalculator.swift
git commit -m "test(bac): Mitchell 2014 Cmax/Tmax fixtures; calibrate kA(ABV) anchors"
```

---

## Task 6: Preserve the gulp instant-absorption invariant

**Files:**
- Test: `siptrackTests/BACCalculatorKineticsTests.swift` (append)

- [ ] **Step 1: Write the gulp test**

```swift
    @Test func gulp_secondDrinkInsideWindow_spikesImmediately() {
        // Two shots 1 min apart: the first is "gulped" → its full mass must register
        // almost immediately, not trickle in. Compare BAC 2 min after the first shot
        // against a single-shot non-gulped baseline at the same elapsed time.
        let profile = maleProfile(weight: 80)
        let shot = DrinkType.presets.first { $0.id == "vodka" }!  // 44 mL @ 40%, gulp window
        let start = Date()
        let gulpedPair = [
            DrinkEntry(id: "a", eventId: "e", drinkTypeId: "vodka", timestamp: start,
                       quantity: 1, comment: nil, volumeOverrideMl: nil, abvOverride: nil),
            DrinkEntry(id: "b", eventId: "e", drinkTypeId: "vodka",
                       timestamp: start.addingTimeInterval(60),
                       quantity: 1, comment: nil, volumeOverrideMl: nil, abvOverride: nil)
        ]
        let at2min = start.addingTimeInterval(120)
        let curve = BACCalculator.bacTimeline(
            entries: gulpedPair, drinkTypes: [shot], profile: profile, eventStart: start
        )
        let bacAt2 = curve.min(by: { abs($0.date.timeIntervalSince(at2min)) < abs($1.date.timeIntervalSince(at2min)) })?.bac ?? 0
        // Both shots gulped/near-instant: ~28 g should be largely present by 2 min.
        // Full Widmark for 2 shots ≈ 0.049; expect well above a slow-absorption floor.
        #expect(bacAt2 > 0.02)
    }
```

- [ ] **Step 2: Run**

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorKineticsTests`
Expected: PASS. If it fails, verify the gulp branch in `integrateBAC` (`absorbed` returns `1.0` for a gulped drink once `since > 0`) and that the first drink's gulp flag is set (second drink within its `T`).

- [ ] **Step 3: Run the WHOLE test target (regression sweep)**

Run: `xcodebuild test -scheme siptrack -destination '...' -only-testing:siptrackTests`
Expected: PASS — core, kinetics, and the existing `BACCalculatorFoodTests` all green.

- [ ] **Step 4: Commit**

```bash
git add siptrackTests/BACCalculatorKineticsTests.swift
git commit -m "test(bac): preserve gulp instant-absorption invariant"
```

---

## Task 7: Update model documentation

**Files:**
- Modify: `SipTrack/Core/BACCalculator.swift` (header comment, lines ~11–34)
- Modify: `.planning/research/BAC-ACCURACY-RESEARCH.md` (§2.1 / §4 note on M-M + kA(ABV))

- [ ] **Step 1: Update the header comment**

Edit the `BACCalculator` file header to state: one-compartment model, **Michaelis–Menten elimination** (Vmax back-calibrated from β at C_ref=0.08, Km=0.004 g/100mL), **concentration-dependent absorption** `kA(%ABV)` calibrated to Mitchell 2014 Tmax/Cmax, solved by 1-minute forward integration; gulp instant-absorption preserved as a UX override. Keep the existing source citations and add Mitchell/Toxics/Jones for the kinetics.

- [ ] **Step 2: Append a note to the research doc**

In `.planning/research/BAC-ACCURACY-RESEARCH.md`, add a short subsection under §4 noting the implemented `kA(%ABV)` anchors and the Mitchell Tmax/Cmax calibration target, and under §2/§3 that elimination is now M-M (not zero-order) with the Vmax calibration relationship.

- [ ] **Step 3: Commit**

```bash
git add SipTrack/Core/BACCalculator.swift .planning/research/BAC-ACCURACY-RESEARCH.md
git commit -m "docs(bac): document M-M elimination + kA(ABV) absorption model"
```

---

## Self-Review

**Spec coverage (model-core portions of `2026-06-06-bac-accuracy-overhaul-design.md`):**
- §3.1 forward integration + M-M + Vmax calibration → Tasks 1–3. ✓
- §3.1a `kA = f(%ABV)` calibrated to Mitchell → Tasks 1 & 5. ✓
- §3.2 elimination acceptance (β at 0.08, longer tail) → Task 4. ✓
- §6 tests (M-M tail, high-BAC regression, Mitchell fixtures, gulp) → Tasks 4–6. ✓
- Public-API stability / preserved gulp invariant → Tasks 2 & 6. ✓
- Dose fidelity (§3.3), verdict reframe (§3.4), honest note (§3.5) → **deferred to Plans 2 & 3** (out of this plan's scope by design).

**Placeholder scan:** none — every step has concrete code/commands. The only conditional is Task 5's anchor tuning, which is genuine TDD calibration against a named fixture, not a placeholder.

**Type consistency:** `michaelisKm` (let), `vmax(beta:)`, `absorptionRateEmpty(abv:)`, `integrateBAC(...)`, `PreparedDrink` used consistently across tasks. `bacAt`/`bacTimeline`/`estimatePeakBAC`/`meanBACForEvent` signatures unchanged from the current file. `BACDataPoint(date:bac:)` matches the existing struct. Test helpers (`maleProfile`, `beer`, `peakAndTmax`) defined before use within the one suite.

**Risk note:** Task 5 calibration cannot be verified on a Windows box — it must run on the macOS build machine. If anchors need tuning, only `absorptionRateEmpty` changes; Km/Vmax/integration stay fixed.
