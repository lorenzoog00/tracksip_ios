# Remove a mistaken drink Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user remove any drink of the active night from the Stats timeline, with a confirmation that shows what removing it does to BAC now and to the peak ahead.

**Architecture:** BAC is recomputed from the entry list on every read, so removal is just `AppState.deleteEntry`. New pure pieces: `BACCalculator.removalImpact` (before/after numbers, full counterfactual) and `HapticSpec.releasesCeilingLatch`. `deleteEntry` gains the missing side effects. `NightStatsSheet` gets the menu and the dialog.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing. No local toolchain: CI's macOS job is the only compile.

**Spec:** `docs/superpowers/specs/2026-11-27-remove-drink-design.md`

## Global Constraints

- Active night only: the remove action shows only while `event.isActive`.
- No change to `integrateBAC` or gulp detection. Removal = entry dropped from the list (the previous drink's gulp is re-evaluated).
- UI copy in English. Numbers with 3 decimals (`%.3f`), like the existing "+0.0xx BAC".
- Only edit already-registered files (no new `.swift` files, so no `project.pbxproj` change).
- Single-line commit messages.

## Review Focus

1. Removing the only drink of the night: dialog shows `0.000` after, meter goes to 0, Live Activity ends its countdown.
2. Removing the drink whose undo toast is still on screen: toast disappears; tapping Undo afterwards can't act on a gone entry.
3. Night ends while the dialog is open: confirming must still delete safely (`deleteEntry` tolerates a non-active event).
4. Ceiling haptic already fired by real drinks, then a mistaken one is removed: latch stays (pinned by `keepsCeilingLatch_whenRealDrinksReachedIt`).
5. Removing a drink logged right after another (gulp): BAC drops more than the "+BAC" label, then rises (pinned by `removalImpact_unGulpsThePreviousDrink`).

---

### Task 1: `BACCalculator.removalImpact` + dialog copy

**Files:**
- Modify: `SipTrack/Core/BACCalculator.swift` (new struct at file scope, new static func after `drinkContributions`)
- Test: `siptrackTests/BACCalculatorKineticsTests.swift` (uses its `maleProfile` / `beer` helpers)

**Interfaces:**
- Produces:
  - `struct BACRemovalImpact: Equatable { let nowBefore, nowAfter, peakAheadBefore, peakAheadAfter, peakSoFarAfter: Double; var message: String }`
  - `static func removalImpact(removing entryId: String, entries: [DrinkEntry], drinkTypes: [DrinkType], profile: UserProfile, eventStart: Date, stomachState: StomachState = .empty, stomachStateTimestamp: Date? = nil, foodEntries: [FoodEntry] = [], asOf now: Date = .now) -> BACRemovalImpact`

- [ ] **Step 1: Write failing tests**
  - `removalImpact_removingOnlyDrink_dropsEverythingToZero`: one beer 30 min before `now`. `nowBefore > 0`; `nowAfter == 0`, `peakAheadAfter == 0`, `peakSoFarAfter == 0`.
  - `removalImpact_afterIsTheNightWithoutTheDrink`: beers at t0 and t0+60m, remove the second, `asOf` t0+75m. `abs(nowAfter - currentBAC([first], asOf:)) < 1e-9`; `nowBefore > nowAfter`.
  - `removalImpact_justLoggedDrink_lowersPeakAheadMoreThanNow`: beers at t0 and t0+60m, `asOf` t0+60m+30s. `nowBefore - nowAfter < 0.002`; `peakAheadBefore - peakAheadAfter > 0.005`.
  - `removalImpact_unGulpsThePreviousDrink`: beers at t0 and t0+2m, remove the second, `asOf` t0+5m. `abs(nowAfter - currentBAC([first], asOf:)) < 1e-9`; `nowAfter < 0.5 * nowBefore`.
  - `removalMessage_showsPeakLineOnlyWhileRising`: `(0.085, 0.071, 0.102, 0.088, 0)` → `"BAC now: 0.085 → 0.071\nPeak ahead: 0.102 → 0.088"`; `(0.085, 0.071, 0.085, 0.071, 0)` → `"BAC now: 0.085 → 0.071"`.
- [ ] **Step 2: Implement.** For `before` (all entries) and `after` (without `entryId`): `bacTimeline`, `currentBAC(asOf: now)`, `futurePeakBAC(timeline, from: now, currentBAC:)`. `peakSoFarAfter = max(nowAfter, max of after-timeline points with date <= now)`. `message`: line 1 always; line 2 when `peakAheadBefore - nowBefore >= 0.001`.
- [ ] **Step 3: Commit** `feat: compute what removing a drink does to BAC now and to the peak ahead`

### Task 2: `HapticSpec.releasesCeilingLatch`

**Files:**
- Modify: `SipTrack/Core/HapticSpec.swift` (next to `firstObservationFires`)
- Test: `siptrackTests/HapticSpecTests.swift`

**Interfaces:**
- Produces: `static func releasesCeilingLatch(peakSoFar: Double, ceiling: Double?) -> Bool`, true only when the ceiling is meaningful (`>= minimumMeaningfulCeiling`) and `peakSoFar < ceiling`.

- [ ] **Step 1: Write failing tests**
  - `releasesCeilingLatch_whenNightNeverReachedItWithoutTheDrink`: `(0.07, 0.08)` → true.
  - `keepsCeilingLatch_whenRealDrinksReachedIt`: `(0.08, 0.08)` → false; `(0.09, 0.08)` → false.
  - `releasesCeilingLatch_noMeaningfulCeiling_isFalse`: `(0.0, nil)` → false; `(0.0, 0.0)` → false.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit** `feat: decide when removing a drink should re-arm the ceiling haptic`

### Task 3: `AppState` removal side effects

**Files:**
- Modify: `SipTrack/State/AppState.swift` — `deleteEntry` (~2035), comments in `startBACRefreshTimer` (~400) and `hasFiredCeilingCrossing` (~437)

**Interfaces:**
- Consumes: Task 1 `removalImpact`, Task 2 `releasesCeilingLatch`.
- Produces: `func removalImpact(ofEntry id: String, now: Date = .now) -> BACRemovalImpact?` (nil when the entry or its event is gone).

- [ ] **Step 1: Implement** `removalImpact(ofEntry:)` with the same event context `currentBAC(for:)` uses.
- [ ] **Step 2: Extend `deleteEntry`.** Before removing, decide the latch release (active event, entry belongs to it, latch set, `releasesCeilingLatch(peakSoFar: impact.peakSoFarAfter, ceiling: Self.ceiling(for:))`). After removing: clear `undoEntry`/`undoTask` when ids match; `activeWarnings = []`; on release, drop the id from `ceilingCrossedEventIds` and restart `startBACRefreshTimer` if `bacTimerTask != nil`; `WatchBridge.shared.pushState()`.
- [ ] **Step 3: Update the two latch comments** ("never un-latches", "nothing else writes the id") to say a drink removal can release it and restarts the task.
- [ ] **Step 4: Commit** `feat: keep the watch, undo toast, warnings and ceiling haptic in step when a drink is removed`

### Task 4: Stats timeline menu + confirmation

**Files:**
- Modify: `SipTrack/Views/Event/NightStatsSheet.swift`

**Interfaces:**
- Consumes: `appState.removalImpact(ofEntry:)`, `appState.deleteEntry(_:)`.

- [ ] **Step 1: Implement.** `DrinkTimelineCard` gets `onRemove: (() -> Void)?`. When non-nil: an `ellipsis` `Menu` (44 pt hit area, accessibility label "More for <name>") with destructive "Remove drink", and the same item in `.contextMenu`. Pass it only when `event?.isActive == true`. The sheet keeps `@State pendingRemoval` (entry + impact computed when chosen) and shows `confirmationDialog` titled "Remove <name> (<h:mm>)?", message `impact.message`, buttons "Remove" (destructive → `deleteEntry`, `Haptics.shared.play(.light)`) and "Cancel".
- [ ] **Step 2: Commit** `feat: remove a mistaken drink from the night timeline`

### Task 5: Ship to dev

- [ ] Push `feat/remove-drink`, open PR into `dev`, bind it, read CI. Confirm in the macOS job log that the new tests ran (`grep removalImpact_`).
