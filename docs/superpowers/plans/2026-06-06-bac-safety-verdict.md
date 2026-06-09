# Safety Verdict Reframe — Implementation Plan (3 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Stop the app from ever implying "you can drive." Base the drive decision on a conservative verdict BAC (upper uncertainty edge, or the projected peak if still rising), warn about impairment *below* the legal limit, and make every "time until…" use the Michaelis–Menten curve — fixing the exact failure that started this work.

**Architecture:** Pure-logic helpers in `BACCalculator` (`driveVerdictBAC`, `ImpairmentTier`, `impairmentTier`) + an `AppState.driveStatus` that combines current/peak/legal into one value object. `WarningSystem` switches to tiered, never-affirmative messaging on the verdict BAC. `ActiveEventView` triggers the banner on the verdict (not the raw level) and counts down with the M-M `hoursToReduceBAC`. One honest copy line about felt-vs-measured intoxication.

**Tech Stack:** Swift, SwiftUI, Swift `Testing`.

---

## File Structure
- **Modify:** `SipTrack/Core/BACCalculator.swift` — verdict helpers + `ImpairmentTier`.
- **Modify:** `SipTrack/Core/WarningSystem.swift` — tiered, never-affirmative driving messaging.
- **Modify:** `SipTrack/State/AppState.swift` — `driveStatus(for:limit:)`; pass `verdictBAC` into `WarningContext`.
- **Modify:** `SipTrack/Views/Event/ActiveEventView.swift` — banner trigger on verdict; M-M countdown; sub-limit non-affirmation copy.
- **Test:** `siptrackTests/DriveVerdictTests.swift` (create).

---

## Task 1: Verdict helpers in `BACCalculator`

**Files:** Modify `BACCalculator.swift`; create `siptrackTests/DriveVerdictTests.swift`.

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import siptrack

struct DriveVerdictTests {

    @Test func verdictBAC_usesUpperBandOrPeak() {
        // Descending: upper edge of the ±20% band dominates.
        #expect(abs(BACCalculator.driveVerdictBAC(current: 0.05, projectedPeak: 0.05) - 0.06) < 1e-9)
        // Rising: the projected peak dominates.
        #expect(BACCalculator.driveVerdictBAC(current: 0.05, projectedPeak: 0.09) == 0.09)
    }

    @Test func impairmentTier_fivePercentIsDangerEvenUnderLegalEighty() {
        // 0.06 verdict, legal limit 0.08 → still "impaired" (do not drive).
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.06, legalLimit: 0.08) == .impaired)
    }

    @Test func impairmentTier_overLegal_andMildAndMinimal() {
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.09, legalLimit: 0.08) == .overLegal)
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.03, legalLimit: 0.08) == .mild)
        #expect(BACCalculator.impairmentTier(verdictBAC: 0.01, legalLimit: 0.08) == .minimal)
    }
}
```

- [ ] **Step 2: Run → FAIL.**

- [ ] **Step 3: Implement** — add near the status helpers:

```swift
    // Impairment relative to driving. The legal limit is a prosecution line, not a safety
    // line: impairment is documented from 0.02 and significant by 0.05 (NHTSA; WHO
    // recommends a 0.05 limit). We never report an affirmative "safe to drive".
    enum ImpairmentTier { case minimal, mild, impaired, overLegal }

    // Conservative BAC for the drive decision: the upper edge of the ±20% band, or the
    // projected peak if BAC is still rising — whichever is higher. Never optimistic.
    static func driveVerdictBAC(current: Double, projectedPeak: Double) -> Double {
        max(current * (1 + bacCV), projectedPeak)
    }

    static func impairmentTier(verdictBAC: Double, legalLimit: Double) -> ImpairmentTier {
        if verdictBAC >= legalLimit { return .overLegal }
        if verdictBAC >= 0.05 { return .impaired }
        if verdictBAC >= 0.02 { return .mild }
        return .minimal
    }
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(safety): driveVerdictBAC + ImpairmentTier`.

---

## Task 2: Tiered, never-affirmative warnings

**Files:** Modify `WarningSystem.swift`; append to `DriveVerdictTests.swift`.

- [ ] **Step 1: Add `verdictBAC` to `WarningContext`**

In `struct WarningContext`, add:
```swift
    let verdictBAC: Double
```

- [ ] **Step 2: Replace the driving branch in `buildWarnings`**

Replace the first `if context.drivingMode { … }` block (the "Do Not Drive" / previous<limit crossing) with tier logic driven by `verdictBAC`, and replace the later `bacApproach` block. The driving block becomes:

```swift
    if context.drivingMode {
        let tier = BACCalculator.impairmentTier(verdictBAC: context.verdictBAC,
                                                legalLimit: context.bacLimit)
        switch tier {
        case .overLegal:
            let hrs = BACCalculator.hoursToReduceBAC(from: context.verdictBAC,
                                                     to: context.bacLimit,
                                                     beta: context.eliminationRate)
            warnings.append(DrinkWarning(
                kind: .bacExceeded, title: "Do Not Drive",
                message: "Estimated BAC \(String(format: "%.3f", context.verdictBAC))% is over your legal limit. Earliest legal in ~\(formatHours(hrs)) — impairment lasts longer.",
                severity: .danger))
        case .impaired:
            warnings.append(DrinkWarning(
                kind: .bacExceeded, title: "Do Not Drive",
                message: "Estimated BAC \(String(format: "%.3f", context.verdictBAC))% — impaired well before the legal limit. Don't drive.",
                severity: .danger))
        case .mild:
            warnings.append(DrinkWarning(
                kind: .bacApproach, title: "Impairment Has Begun",
                message: "Even at \(String(format: "%.3f", context.verdictBAC))% your reaction time is affected. The app can't confirm it's safe to drive.",
                severity: .warn))
        case .minimal:
            break  // never an affirmative "safe to drive"
        }
    }
```

Delete the old standalone `bacApproach` driving block lower down (its role is now the `.mild` tier).

- [ ] **Step 3: Add the `formatHours` helper** at file scope in `WarningSystem.swift`:

```swift
func formatHours(_ hours: Double) -> String {
    guard hours > 0 else { return "0m" }
    let h = Int(hours)
    let m = Int((hours - Double(h)) * 60)
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}
```

- [ ] **Step 4: Test never-affirmative + tier copy**

Append to `DriveVerdictTests`:
```swift
    @Test func warnings_neverAffirmSafeToDrive_belowImpairment() {
        let ctx = WarningContext(
            currentBAC: 0.01, previousBAC: 0.0, drivingMode: true, bacLimit: 0.08,
            drinksLastHour: 0, totalCalories: 0,
            previousStage: IntoxicationStage.stage(for: 0.0),
            currentStage: IntoxicationStage.stage(for: 0.01),
            prefs: NotificationPreferences(), eliminationRate: 0.015, verdictBAC: 0.012)
        let ws = buildWarnings(context: ctx)
        #expect(!ws.contains { $0.message.localizedCaseInsensitiveContains("safe to drive") && $0.severity != .warn })
        #expect(!ws.contains { $0.kind == .bacExceeded })
    }

    @Test func warnings_fivePercentUnderLegal_isDoNotDrive() {
        let ctx = WarningContext(
            currentBAC: 0.05, previousBAC: 0.04, drivingMode: true, bacLimit: 0.08,
            drinksLastHour: 1, totalCalories: 0,
            previousStage: IntoxicationStage.stage(for: 0.04),
            currentStage: IntoxicationStage.stage(for: 0.05),
            prefs: NotificationPreferences(), eliminationRate: 0.015, verdictBAC: 0.06)
        #expect(buildWarnings(context: ctx).contains { $0.title == "Do Not Drive" })
    }
```

> NOTE at execution: confirm the real `IntoxicationStage` API for building a stage from a BAC (the test uses `IntoxicationStage.stage(for:)` — adjust to the actual factory if named differently).

- [ ] **Step 5: Run → PASS. Commit** `feat(safety): tiered never-affirmative drive warnings on verdict BAC`.

---

## Task 3: `AppState.driveStatus`

**Files:** Modify `AppState.swift`.

- [ ] **Step 1: Add the value object + computation**

```swift
    struct DriveStatus {
        let verdictBAC: Double
        let tier: BACCalculator.ImpairmentTier
        let currentBAC: Double
    }

    /// Conservative drive verdict for an event: current BAC, the projected peak from now
    /// (in case BAC is still rising), combined into the verdict BAC and impairment tier.
    func driveStatus(for eventId: String, limit: Double) -> DriveStatus {
        guard let event = events.first(where: { $0.id == eventId }) else {
            return DriveStatus(verdictBAC: 0, tier: .minimal, currentBAC: 0)
        }
        let now = Date()
        let current = currentBAC(for: eventId)
        let eventEntries = entries.filter { $0.eventId == eventId }
        let eventFood    = foodEntries.filter { $0.eventId == eventId }
        let timeline = BACCalculator.bacTimeline(
            entries: eventEntries, drinkTypes: allDrinkTypes, profile: userProfile,
            eventStart: event.startTime,
            stomachState: event.stomachState ?? .empty,
            stomachStateTimestamp: event.stomachStateTimestamp ?? event.startTime,
            foodEntries: eventFood)
        let projectedPeak = timeline.filter { $0.date >= now }.map(\.bac).max() ?? current
        let verdict = BACCalculator.driveVerdictBAC(current: current, projectedPeak: projectedPeak)
        return DriveStatus(verdictBAC: verdict,
                           tier: BACCalculator.impairmentTier(verdictBAC: verdict, legalLimit: limit),
                           currentBAC: current)
    }
```

- [ ] **Step 2: Pass `verdictBAC` into `WarningContext`** where it is constructed (in `checkWarnings`, ~line 1483). Compute the verdict there:
```swift
        let verdict = driveStatus(for: eventId, limit: bacLimit).verdictBAC
```
and add `verdictBAC: verdict` to the `WarningContext(...)` initializer call. (Locate the `bacLimit` already in scope there; if not, use `event.bacLimit ?? userProfile.resolvedBACLimit`.)

- [ ] **Step 3: Commit** `feat(safety): AppState.driveStatus + verdict in WarningContext`.

---

## Task 4: `ActiveEventView` — banner on verdict, M-M countdown, non-affirmation

**Files:** Modify `ActiveEventView.swift`.

- [ ] **Step 1: Trigger the banner on the verdict, not the raw level**

Replace:
```swift
        let overLimit = event.drivingMode && currentBAC >= bacLimit
```
with:
```swift
        let drive = appState.driveStatus(for: eventId, limit: bacLimit)
        let showDriveWarning = event.drivingMode &&
            (drive.tier == .overLegal || drive.tier == .impaired)
```
and change the banner condition `if overLimit {` → `if showDriveWarning {`, passing `drive.verdictBAC` and `bacLimit` to `DriveWarningBanner`.

- [ ] **Step 2: M-M countdown in `DriveWarningBanner`**

Replace its `hoursRemaining` with the M-M time from the (verdict) BAC down to the limit:
```swift
    private var hoursRemaining: Double {
        BACCalculator.hoursToReduceBAC(from: bac, to: bacLimit, beta: beta)
    }
```
(The `bac` passed in is now `drive.verdictBAC`.)

- [ ] **Step 3: Sub-limit non-affirmation line**

Under the BAC hero, when `event.drivingMode && drive.tier == .mild`, show a small warn line; when `.minimal`, show a neutral line that never says "safe":
```swift
        if event.drivingMode {
            switch drive.tier {
            case .mild:
                Text("Impairment has begun — the app can't confirm it's safe to drive.")
                    .font(.system(size: 11)).foregroundStyle(AppColors.amber ?? .orange)
            case .minimal:
                Text("Effects may still be present. This app can't tell you it's safe to drive.")
                    .font(.system(size: 11)).foregroundStyle(AppColors.textTertiary)
            default: EmptyView()
            }
        }
```
> NOTE at execution: use the real accent/amber color token from `AppColors`; remove any existing affirmative "safe to drive at X" / green-OK affordance in the driving UI.

- [ ] **Step 4: Build check (device). Commit** `feat(safety): drive banner on verdict + M-M countdown + non-affirmation copy`.

---

## Task 5: Honest felt-vs-measured note

**Files:** Modify `ActiveEventView.swift` (BAC hero footnote) or `LearnView`.

- [ ] **Step 1:** Add one dismissible/static line near the BAC number:
```swift
Text("You may feel more impaired than your BAC suggests — especially while it's rising. When in doubt, don't drive.")
    .font(.system(size: 10)).foregroundStyle(AppColors.textTertiary)
    .multilineTextAlignment(.center)
```
- [ ] **Step 2: Commit** `feat(safety): honest felt-vs-measured intoxication note`.

---

## Self-Review
- **Spec coverage:** §3.4 verdict reframe → Tasks 1–4; §3.5 honest note → Task 5; M-M time-to-limit → Tasks 2 & 4. ✓
- **Placeholder scan:** Tasks 2/3/4 carry explicit "confirm API at execution" notes for `IntoxicationStage.stage(for:)`, the `WarningContext` call site, and `AppColors` tokens — these are real lookups, not vague TODOs.
- **Type consistency:** `driveVerdictBAC(current:projectedPeak:)`, `impairmentTier(verdictBAC:legalLimit:)`, `ImpairmentTier`, `DriveStatus`, `WarningContext.verdictBAC`, `hoursToReduceBAC(from:to:beta:)` used consistently.
- **Risk:** logic (Tasks 1–3) is unit-tested; UI (Task 4–5) needs a device build. No public model signatures change.
