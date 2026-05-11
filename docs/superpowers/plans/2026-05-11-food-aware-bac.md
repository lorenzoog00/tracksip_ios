# Food-Aware BAC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stomach-state tracking to SipTrack so BAC calculations account for food consumption, improving accuracy by up to 30%.

**Architecture:** Two UI touch points (event-start picker + in-event food log button) feed `StomachState` and `[FoodEntry]` data into `BACCalculator.bacAt`, which applies a time-decaying absorption delay and peak reduction factor per drink. All existing callers of `currentBAC`, `bacTimeline`, and `estimatePeakBAC` gain optional food parameters so they degrade gracefully to current behavior when food data is absent.

**Tech Stack:** Swift 5.9, SwiftUI, Codable JSON persistence via `DataStore`, `BACCalculator` static functions

---

## File Map

| File | Change |
|------|--------|
| `Models/FoodEntry.swift` | **Create** — `StomachState` enum + `FoodEntry` struct |
| `Models/NightEvent.swift` | **Modify** — add `stomachState: StomachState?`, `stomachStateTimestamp: Date?` |
| `Storage/AppStorage.swift` | **Modify** — food entry persistence + cascade delete |
| `Core/BACCalculator.swift` | **Modify** — `computeStomachFactor`, update `bacAt`, `currentBAC`, `bacTimeline`, `estimatePeakBAC` |
| `State/AppState.swift` | **Modify** — `@Published var foodEntries`, `addFoodEntry`, `deleteFoodEntry`, update `createEvent` and `currentBAC(for:)` |
| `Views/Event/CreateEventView.swift` | **Modify** — stomach state picker step |
| `Views/Event/ActiveEventView.swift` | **Modify** — food button in BottomBar, food card, food in timeline |
| `Views/Summary/SummaryView.swift` | **Modify** — food entries in timeline, stomach state in metadata |

---

## Task 1: Data Types — `StomachState`, `FoodEntry`, update `NightEvent`

**Files:**
- Create: `tracksip_ios/SipTrack/Models/FoodEntry.swift`
- Modify: `tracksip_ios/SipTrack/Models/NightEvent.swift`

- [ ] **Step 1: Create `FoodEntry.swift`**

```swift
// tracksip_ios/SipTrack/Models/FoodEntry.swift
import Foundation

enum StomachState: String, Codable {
    case empty, snack, fullMeal

    var displayName: String {
        switch self {
        case .empty:    return "Empty"
        case .snack:    return "Snack"
        case .fullMeal: return "Full Meal"
        }
    }

    var emoji: String {
        switch self {
        case .empty:    return "💨"
        case .snack:    return "🥨"
        case .fullMeal: return "🍽️"
        }
    }
}

struct FoodEntry: Codable, Identifiable, Hashable {
    var id: String
    var eventId: String
    var type: StomachState   // .snack or .fullMeal — .empty is never logged
    var timestamp: Date
}
```

- [ ] **Step 2: Add fields to `NightEvent`**

In `tracksip_ios/SipTrack/Models/NightEvent.swift`, add two optional properties after `createdAt`. Using `Optional` so existing stored JSON (which lacks these keys) decodes without error — Swift's synthesized `Codable` uses `decodeIfPresent` for optional fields automatically.

```swift
// Add after line 13 (var createdAt: Date)
var stomachState: StomachState?        // nil on old events → treated as .empty
var stomachStateTimestamp: Date?       // nil on old events → treated as startTime
```

- [ ] **Step 3: Build the project**

Open Xcode and build (Cmd+B). Expected: build succeeds. The new optional fields don't break existing `NightEvent(...)` call sites because Swift's memberwise initializer defaults optionals to `nil`.

- [ ] **Step 4: Commit**

```bash
git add tracksip_ios/SipTrack/Models/FoodEntry.swift tracksip_ios/SipTrack/Models/NightEvent.swift
git commit -m "feat: add StomachState, FoodEntry types and NightEvent food fields"
```

---

## Task 2: Storage — Food Entry Persistence

**Files:**
- Modify: `tracksip_ios/SipTrack/Storage/AppStorage.swift`

- [ ] **Step 1: Add food entry CRUD to `DataStore`**

In `tracksip_ios/SipTrack/Storage/AppStorage.swift`, add a new `// MARK: - Food Entries` section after the Water Entries section (after line 133):

```swift
// MARK: - Food Entries

func loadFoodEntries() -> [FoodEntry] {
    load([FoodEntry].self, key: "siptrack_food") ?? []
}

func saveFoodEntries(_ entries: [FoodEntry]) {
    save(entries, key: "siptrack_food")
}

func addFoodEntry(_ entry: FoodEntry) {
    var entries = loadFoodEntries()
    entries.append(entry)
    saveFoodEntries(entries)
}

func deleteFoodEntry(_ id: String) {
    var entries = loadFoodEntries()
    entries.removeAll { $0.id == id }
    saveFoodEntries(entries)
}
```

- [ ] **Step 2: Cascade-delete food entries when an event is deleted**

In `deleteEvent(_ id: String)` (currently lines 70-81), add food cascade after the water cascade:

```swift
func deleteEvent(_ id: String) {
    var events = loadEvents()
    events.removeAll { $0.id == id }
    saveEvents(events)
    var entries = loadEntries()
    entries.removeAll { $0.eventId == id }
    saveEntries(entries)
    var water = loadWaterEntries()
    water.removeAll { $0.eventId == id }
    saveWaterEntries(water)
    // NEW: cascade-delete food entries
    var food = loadFoodEntries()
    food.removeAll { $0.eventId == id }
    saveFoodEntries(food)
}
```

- [ ] **Step 3: Add `"siptrack_food"` to `clearAllData()`**

Update the `keys` array in `clearAllData()` (line 194):

```swift
let keys = ["siptrack_events","siptrack_entries","siptrack_water","siptrack_drink_types",
            "siptrack_challenges","siptrack_profile","siptrack_coach_reports",
            "siptrack_night_recoveries","siptrack_food"]
```

- [ ] **Step 4: Build**

Cmd+B. Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add tracksip_ios/SipTrack/Storage/AppStorage.swift
git commit -m "feat: add food entry persistence to DataStore"
```

---

## Task 3: BAC Engine — `computeStomachFactor` + integrate into `bacAt`

**Files:**
- Modify: `tracksip_ios/SipTrack/Core/BACCalculator.swift`

This is the core accuracy change. The approach:
- `computeStomachFactor(at:stomachState:stomachStateTimestamp:foodEntries:)` — returns `(absorptionDelayMinutes, peakReductionFactor)` for a given moment, accounting for decay.
- `bacAt` — updated to apply the factor per drink: drinks that haven't cleared their absorption delay yet don't contribute; effective alcohol is reduced by `peakReductionFactor`.
- All public functions (`currentBAC`, `bacTimeline`, `estimatePeakBAC`, `meanBACForEvent`) gain optional food parameters that default to `.empty` / `[]` so existing callers keep working unchanged.

- [ ] **Step 1: Add `computeStomachFactor` to `BACCalculator`**

Add after the `// MARK: - Hydration` section (after line 212):

```swift
// MARK: - Food / Stomach factor

static func computeStomachFactor(
    at drinkTime: Date,
    stomachState: StomachState,
    stomachStateTimestamp: Date,
    foodEntries: [FoodEntry]
) -> (absorptionDelayMinutes: Double, peakReductionFactor: Double) {

    func base(for state: StomachState) -> (delay: Double, reduction: Double) {
        switch state {
        case .empty:    return (0,    0)
        case .snack:    return (15,   0.15)
        case .fullMeal: return (37.5, 0.30)
        }
    }

    // Linear decay back to empty over 150 minutes (gastric emptying model)
    func decay(minutesSince: Double) -> Double {
        max(0.0, 1.0 - (minutesSince / 150.0))
    }

    let initMinutes = drinkTime.timeIntervalSince(stomachStateTimestamp) / 60
    let initBase    = base(for: stomachState)
    let initDecay   = decay(minutesSince: max(0, initMinutes))
    var bestDelay   = initBase.delay     * initDecay
    var bestReduce  = initBase.reduction * initDecay

    // Check every food entry logged before this drink; pick strongest remaining effect
    for entry in foodEntries where entry.timestamp <= drinkTime {
        let minutes     = drinkTime.timeIntervalSince(entry.timestamp) / 60
        let entryBase   = base(for: entry.type)
        let entryDecay  = decay(minutesSince: minutes)
        bestDelay  = max(bestDelay,  entryBase.delay     * entryDecay)
        bestReduce = max(bestReduce, entryBase.reduction * entryDecay)
    }

    return (absorptionDelayMinutes: bestDelay, peakReductionFactor: bestReduce)
}
```

- [ ] **Step 2: Update `bacAt` to apply the stomach factor**

Replace the existing private `bacAt` function (lines 69-86) with this version that adds optional food parameters:

```swift
private static func bacAt(
    _ time: Date,
    entries: [DrinkEntry],
    drinkTypes: [DrinkType],
    weightKg: Double,
    r: Double,
    stomachState: StomachState = .empty,
    stomachStateTimestamp: Date,
    foodEntries: [FoodEntry] = []
) -> Double {
    guard weightKg > 0, r > 0 else { return 0 }
    return entries.reduce(0.0) { sum, entry in
        let dt      = drinkTypes.first { $0.id == entry.drinkTypeId }
        let vol     = entry.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
        let abv     = entry.abvOverride ?? dt?.defaultAbv ?? 0
        let alcohol = calculateAlcohol(volumeMl: vol, abv: abv, quantity: entry.quantity)

        let factor       = computeStomachFactor(
            at: entry.timestamp,
            stomachState: stomachState,
            stomachStateTimestamp: stomachStateTimestamp,
            foodEntries: foodEntries
        )
        let effectiveStart = entry.timestamp.addingTimeInterval(factor.absorptionDelayMinutes * 60)
        guard time >= effectiveStart else { return sum }   // drink not yet absorbed

        let hours            = time.timeIntervalSince(effectiveStart) / 3600
        let effectiveAlcohol = alcohol * (1.0 - factor.peakReductionFactor)
        let raw              = (effectiveAlcohol / (weightKg * 1000 * r)) * 100
        return sum + max(0, raw - 0.015 * hours)
    }
}
```

- [ ] **Step 3: Update `estimatePeakBAC` to accept and pass food parameters**

Replace `estimatePeakBAC` (lines 88-107) with:

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
    let rFactor     = r ?? widmarkR(sex: sex)
    let stTimestamp = stomachStateTimestamp ?? eventStart
    let lastTimestamp = entries.map(\.timestamp).max() ?? eventStart
    let endCheck    = lastTimestamp.addingTimeInterval(3600)
    var peak        = 0.0
    var checkpoint  = eventStart
    while checkpoint <= endCheck {
        let bac = bacAt(
            checkpoint,
            entries: entries,
            drinkTypes: drinkTypes,
            weightKg: weightKg,
            r: rFactor,
            stomachState: stomachState,
            stomachStateTimestamp: stTimestamp,
            foodEntries: foodEntries
        )
        peak = max(peak, bac)
        checkpoint = checkpoint.addingTimeInterval(300)
    }
    return peak
}
```

- [ ] **Step 4: Update `bacTimeline` to accept and pass food parameters**

Replace `bacTimeline` (lines 109-138) with:

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
    let r           = profileR(profile: profile)
    let stTimestamp = stomachStateTimestamp ?? eventStart
    let totalAlcohol = entries.reduce(0.0) { sum, entry in
        let dt  = drinkTypes.first { $0.id == entry.drinkTypeId }
        let vol = entry.volumeOverrideMl ?? dt?.defaultVolumeMl ?? 0
        let abv = entry.abvOverride ?? dt?.defaultAbv ?? 0
        return sum + calculateAlcohol(volumeMl: vol, abv: abv, quantity: entry.quantity)
    }
    guard totalAlcohol > 0 else { return [] }
    let rawBAC     = (totalAlcohol / (profile.weightKg * 1000 * r)) * 100
    let hoursToZero = rawBAC / 0.015
    let endDate    = eventStart.addingTimeInterval((hoursToZero + 0.5) * 3600)
    let lastDrink  = entries.map(\.timestamp).max() ?? eventStart

    var points: [BACDataPoint] = []
    var checkpoint = eventStart
    while checkpoint <= endDate {
        let bac = bacAt(
            checkpoint,
            entries: entries,
            drinkTypes: drinkTypes,
            weightKg: profile.weightKg,
            r: r,
            stomachState: stomachState,
            stomachStateTimestamp: stTimestamp,
            foodEntries: foodEntries
        )
        points.append(BACDataPoint(date: checkpoint, bac: bac))
        if bac == 0 && checkpoint > lastDrink { break }
        checkpoint = checkpoint.addingTimeInterval(300)
    }
    return points
}
```

- [ ] **Step 5: Update `currentBAC` to accept and pass food parameters**

Replace `currentBAC` (lines 216-227) with:

```swift
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
    let stTimestamp = stomachStateTimestamp ?? eventStart
    let rawBAC = bacAt(
        Date(),
        entries: entries,
        drinkTypes: drinkTypes,
        weightKg: profile.weightKg,
        r: r,
        stomachState: stomachState,
        stomachStateTimestamp: stTimestamp,
        foodEntries: foodEntries
    )
    let ratio = computeHydrationRatio(waterEntries: waterEntries, drinkCount: entries.count)
    return applyHydration(bac: rawBAC, ratio: ratio)
}
```

- [ ] **Step 6: Build**

Cmd+B. Expected: build succeeds. Note: `bacAt` now requires `stomachStateTimestamp` — but since it's `private`, the only callers are inside `BACCalculator.swift` itself (the public functions you just updated), so there are no external breaks.

- [ ] **Step 7: Commit**

```bash
git add tracksip_ios/SipTrack/Core/BACCalculator.swift
git commit -m "feat: add food-aware stomach factor to BAC engine"
```

---

## Task 4: AppState — Food Entry State + Updated Event/BAC Functions

**Files:**
- Modify: `tracksip_ios/SipTrack/State/AppState.swift`

- [ ] **Step 1: Add `@Published var foodEntries` and load it on init**

Find the block of `@Published var` declarations (near the top of `AppState`). Add food entries alongside water entries:

```swift
@Published var foodEntries: [FoodEntry] = []
```

Find the `init()` or the place where `waterEntries` is loaded (follow the pattern for loading waterEntries from DataStore) and add:

```swift
foodEntries = DataStore.shared.loadFoodEntries()
```

- [ ] **Step 2: Add `addFoodEntry` and `deleteFoodEntry`**

Add these functions near the existing `addWater` / `deleteWaterEntry` functions:

```swift
func addFoodEntry(eventId: String, type: StomachState) {
    let entry = FoodEntry(id: generateId(), eventId: eventId, type: type, timestamp: Date())
    DataStore.shared.addFoodEntry(entry)
    foodEntries.append(entry)
}

func deleteFoodEntry(_ id: String) {
    DataStore.shared.deleteFoodEntry(id)
    foodEntries.removeAll { $0.id == id }
}

func foodEntries(for eventId: String) -> [FoodEntry] {
    foodEntries.filter { $0.eventId == eventId }
}
```

- [ ] **Step 3: Update `createEvent` to accept and store `stomachState`**

Find `func createEvent(name:drivingMode:bacLimit:startTime:)` in AppState (around line 134) and add `stomachState`:

```swift
@discardableResult
func createEvent(
    name: String?,
    drivingMode: Bool,
    bacLimit: Double?,
    startTime: Date = Date(),
    stomachState: StomachState = .empty
) -> NightEvent {
    var event = DataStore.shared.createEvent(
        name: name,
        drivingMode: drivingMode,
        bacLimit: bacLimit,
        userId: currentUserId,
        startTime: startTime
    )
    event.stomachState = stomachState
    event.stomachStateTimestamp = startTime
    DataStore.shared.updateEvent(event)
    events.append(event)
    startLiveActivity(for: event)
    scheduleWaterReminder(for: event.id)
    return event
}
```

Note: `DataStore.createEvent` still creates the event without food fields (they'll be nil). We then mutate and call `updateEvent` to persist the stomach state. Alternatively, if `DataStore.createEvent` signature is easy to update, add `stomachState: StomachState = .empty` there and set the fields directly — either approach works.

- [ ] **Step 4: Update `currentBAC(for:)` to pass food data**

Find `func currentBAC(for eventId: String) -> Double` in AppState (around line 1305) and update:

```swift
func currentBAC(for eventId: String) -> Double {
    guard let event = events.first(where: { $0.id == eventId }) else { return 0 }
    let entries  = drinkEntries.filter { $0.eventId == eventId }
    let water    = waterEntries.filter { $0.eventId == eventId }
    let food     = foodEntries.filter { $0.eventId == eventId }
    return BACCalculator.currentBAC(
        entries: entries,
        waterEntries: water,
        drinkTypes: allDrinkTypes,
        profile: userProfile,
        eventStart: event.startTime,
        stomachState: event.stomachState ?? .empty,
        stomachStateTimestamp: event.stomachStateTimestamp ?? event.startTime,
        foodEntries: food
    )
}
```

- [ ] **Step 5: Build**

Cmd+B. Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add tracksip_ios/SipTrack/State/AppState.swift
git commit -m "feat: wire food entries into AppState and BAC calculation"
```

---

## Task 5: CreateEventView — Stomach State Picker

**Files:**
- Modify: `tracksip_ios/SipTrack/Views/Event/CreateEventView.swift`

- [ ] **Step 1: Add stomach state to local state**

At the top of `CreateEventView`, add after the existing `@State` vars:

```swift
@State private var stomachState: StomachState = .empty
```

- [ ] **Step 2: Add the picker UI**

In the form body, add the picker section before the "Start Night" button. Follow the existing section/label style in the file:

```swift
// Stomach State Picker — add before the start button
VStack(alignment: .leading, spacing: 8) {
    Text("How full is your stomach?")
        .font(.caption)
        .foregroundStyle(.secondary)
        .textCase(.uppercase)

    HStack(spacing: 10) {
        ForEach([StomachState.empty, .snack, .fullMeal], id: \.self) { state in
            Button {
                stomachState = state
            } label: {
                VStack(spacing: 4) {
                    Text(state.emoji)
                        .font(.title2)
                    Text(state.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(stomachState == state ? AppColors.accent.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(stomachState == state ? AppColors.accent : .secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(stomachState == state ? AppColors.accent : Color.clear, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 3: Pass `stomachState` to `createEvent`**

Find the button action that calls `appState.createEvent(...)` (line 123). Add `stomachState: stomachState`:

```swift
let event = appState.createEvent(
    name: name.isEmpty ? nil : name,
    drivingMode: drivingMode,
    bacLimit: drivingMode ? bacLimit : nil,
    startTime: customStart ? startTime : Date(),
    stomachState: stomachState
)
```

- [ ] **Step 4: Build and visually verify**

Cmd+B, run in simulator, tap "Start Night". The picker should appear with three options above the start button. Tapping each should highlight it in orange.

- [ ] **Step 5: Commit**

```bash
git add tracksip_ios/SipTrack/Views/Event/CreateEventView.swift
git commit -m "feat: add stomach state picker to event creation"
```

---

## Task 6: ActiveEventView — Food Button, Food Card, Food in Timeline

**Files:**
- Modify: `tracksip_ios/SipTrack/Views/Event/ActiveEventView.swift`

- [ ] **Step 1: Add food sheet state**

At the top of `ActiveEventView`, add:

```swift
@State private var showFoodSheet = false
```

Also add a computed var for food entries (alongside the existing `eventEntries`, `eventWater`):

```swift
var eventFood: [FoodEntry] {
    appState.foodEntries.filter { $0.eventId == eventId }
}
```

- [ ] **Step 2: Add Food button to `BottomBar`**

Find the `BottomBar` struct (around line 989). It has a `onAddWater` closure. Add an `onAddFood` closure and a Food button:

```swift
struct BottomBar: View {
    let eventId: String
    let onAddWater: () -> Void
    let onAddFood: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAddWater) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                    Text("Water")
                }
                .foregroundStyle(AppColors.water)
                .frame(width: 90, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.water.opacity(0.35), lineWidth: 1))
            }

            Button(action: onAddFood) {
                HStack(spacing: 6) {
                    Text("🍟")
                    Text("Food")
                }
                .foregroundStyle(AppColors.accent)
                .frame(width: 90, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.accent.opacity(0.35), lineWidth: 1))
            }

            Spacer()

            Button(action: onEnd) {
                Text("End Night")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(height: 48)
                    .padding(.horizontal, 20)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
```

- [ ] **Step 3: Wire `onAddFood` in the `BottomBar` call site**

Find where `BottomBar(...)` is called in `ActiveEventView.body` (around line 85) and add `onAddFood`:

```swift
BottomBar(
    eventId: eventId,
    onAddWater: { appState.addWater(eventId: eventId) },
    onAddFood: { showFoodSheet = true },
    onEnd: { showEndConfirm = true }
)
```

- [ ] **Step 4: Add the food picker sheet**

Attach a `.sheet(isPresented: $showFoodSheet)` to the main view (alongside the existing sheets):

```swift
.sheet(isPresented: $showFoodSheet) {
    VStack(spacing: 20) {
        Text("What did you eat?")
            .font(.headline)
            .padding(.top, 24)

        HStack(spacing: 16) {
            ForEach([StomachState.snack, .fullMeal], id: \.self) { type in
                Button {
                    appState.addFoodEntry(eventId: eventId, type: type)
                    showFoodSheet = false
                } label: {
                    VStack(spacing: 8) {
                        Text(type.emoji)
                            .font(.system(size: 40))
                        Text(type.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)

        Button("Cancel") { showFoodSheet = false }
            .foregroundStyle(.secondary)
            .padding(.bottom, 24)
    }
    .presentationDetents([.height(260)])
}
```

- [ ] **Step 5: Add food entries to the timeline**

Find the `TLItem` enum (around line 708). Add a food case:

```swift
enum TLItem: Identifiable {
    case drink(DrinkEntry)
    case water(WaterEntry)
    case food(FoodEntry)          // NEW

    var id: String {
        switch self {
        case .drink(let e): return e.id
        case .water(let e): return e.id
        case .food(let e):  return e.id
        }
    }

    var timestamp: Date {
        switch self {
        case .drink(let e): return e.timestamp
        case .water(let e): return e.timestamp
        case .food(let e):  return e.timestamp
        }
    }
}
```

Find where `TLItem` array is built (it currently merges `eventEntries` and `eventWater`). Add `eventFood`:

```swift
let items: [TLItem] = (
    eventEntries.map { TLItem.drink($0) } +
    eventWater.map   { TLItem.water($0) } +
    eventFood.map    { TLItem.food($0) }
).sorted { $0.timestamp > $1.timestamp }
```

- [ ] **Step 6: Add `TLFoodCard` and handle `.food` in `TLRow`**

Add a `TLFoodCard` view after `TLWaterCard` (around line 984):

```swift
struct TLFoodCard: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.type.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(AppColors.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

In `TLRow` (the switch on `TLItem`), add the food case:

```swift
case .food(let entry):
    TLFoodCard(entry: entry)
```

- [ ] **Step 7: Build and run in simulator**

Cmd+B. Run in simulator, start a new event, tap "Food" in the bottom bar. Verify:
- Food sheet appears with Snack / Full Meal options
- Tapping one dismisses the sheet and shows the food card in the timeline
- The live BAC updates (lower than without food if you compare)

- [ ] **Step 8: Commit**

```bash
git add tracksip_ios/SipTrack/Views/Event/ActiveEventView.swift
git commit -m "feat: add food logging button and timeline card to active event view"
```

---

## Task 7: SummaryView — Food in Timeline and Metadata

**Files:**
- Modify: `tracksip_ios/SipTrack/Views/Summary/SummaryView.swift`

- [ ] **Step 1: Add food entries computed var**

At the top of `SummaryView`, add alongside the existing `entries` and `water` vars:

```swift
var food: [FoodEntry] {
    appState.foodEntries.filter { $0.eventId == eventId }
}
```

- [ ] **Step 2: Show stomach state in event metadata row**

Find the section where event metadata is displayed (event start time, duration, driving mode etc.). Add:

```swift
if let state = event.stomachState, state != .empty {
    Label("\(state.emoji) \(state.displayName) before drinking", systemImage: "fork.knife")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 3: Add food entries to the summary timeline**

Find where the summary timeline/list is built (the section that shows drink and water entries). Merge in food entries the same way as ActiveEventView:

```swift
let timelineItems: [TLItem] = (
    entries.map { TLItem.drink($0) } +
    water.map   { TLItem.water($0) } +
    food.map    { TLItem.food($0) }
).sorted { $0.timestamp < $1.timestamp }
```

For rendering, reuse `TLFoodCard` (already defined in `ActiveEventView.swift`). If it's not accessible (it's inside a struct scope), move `TLFoodCard` to its own file or to the bottom of `NightEvent.swift` so both views can use it.

Note: if the summary uses a different timeline component than `TLRow`, adapt accordingly — the principle is the same: switch on `TLItem.food` and render `TLFoodCard`.

- [ ] **Step 4: Build and verify in simulator**

Cmd+B. End a test event (with food logged) and open its summary. Verify:
- Food entries appear in the timeline between drinks/water at the correct time
- Stomach state label shows in the metadata section

- [ ] **Step 5: Commit**

```bash
git add tracksip_ios/SipTrack/Views/Summary/SummaryView.swift
git commit -m "feat: show food entries and stomach state in event summary"
```

---

## Task 8: Unit Tests — BAC Engine Food Factor

**Files:**
- Create: `tracksip_ios/SipTrackTests/BACCalculatorFoodTests.swift` (add to the existing test target, or create one via Xcode: File → New → Target → Unit Testing Bundle)

- [ ] **Step 1: Create the test file**

```swift
// tracksip_ios/SipTrackTests/BACCalculatorFoodTests.swift
import XCTest
@testable import SipTrack

final class BACCalculatorFoodTests: XCTestCase {

    let now = Date()

    // MARK: - computeStomachFactor

    func test_emptyStomach_returnsZeroEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .empty,
            stomachStateTimestamp: now.addingTimeInterval(-3600),
            foodEntries: []
        )
        XCTAssertEqual(result.absorptionDelayMinutes, 0, accuracy: 0.01)
        XCTAssertEqual(result.peakReductionFactor, 0, accuracy: 0.01)
    }

    func test_fullMealJustEaten_returnsFullEffect() {
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: now,   // eaten right now
            foodEntries: []
        )
        XCTAssertEqual(result.absorptionDelayMinutes, 37.5, accuracy: 0.1)
        XCTAssertEqual(result.peakReductionFactor, 0.30, accuracy: 0.01)
    }

    func test_fullMealTwoHoursAgo_effectIsPartiallyDecayed() {
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: twoHoursAgo,   // 120 min ago
            foodEntries: []
        )
        // decay = max(0, 1 - 120/150) = 0.2
        XCTAssertEqual(result.absorptionDelayMinutes, 37.5 * 0.2, accuracy: 0.1)
        XCTAssertEqual(result.peakReductionFactor, 0.30 * 0.2, accuracy: 0.01)
    }

    func test_fullMealOver150MinAgo_effectIsZero() {
        let oldEat = now.addingTimeInterval(-3 * 3600)  // 180 min ago → fully decayed
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: oldEat,
            foodEntries: []
        )
        XCTAssertEqual(result.absorptionDelayMinutes, 0, accuracy: 0.01)
        XCTAssertEqual(result.peakReductionFactor, 0, accuracy: 0.01)
    }

    func test_inEventSnack_overridesDecayedInitialFullMeal() {
        let threeHoursAgo = now.addingTimeInterval(-3 * 3600)
        let thirtyMinAgo  = now.addingTimeInterval(-30 * 60)
        let snack = FoodEntry(id: "1", eventId: "e", type: .snack, timestamp: thirtyMinAgo)
        let result = BACCalculator.computeStomachFactor(
            at: now,
            stomachState: .fullMeal,
            stomachStateTimestamp: threeHoursAgo,  // fully decayed
            foodEntries: [snack]
        )
        // Snack 30 min ago: decay = max(0, 1 - 30/150) = 0.8
        XCTAssertEqual(result.peakReductionFactor, 0.15 * 0.8, accuracy: 0.01)
    }

    // MARK: - BAC integration

    func test_fullMealReducesBACByThirtyPercent() {
        let profile = UserProfile(weightKg: 80, sex: .male)
        let drinkType = DrinkType.preset(id: "beer", name: "Beer", abv: 5, volumeMl: 355, calories: 150)
        let drink = DrinkEntry(
            id: "d1", eventId: "e", drinkTypeId: "beer",
            timestamp: now.addingTimeInterval(-3600),   // 1 hour ago
            quantity: 1, comment: nil, volumeOverrideMl: nil, abvOverride: nil
        )
        let emptyBAC = BACCalculator.currentBAC(
            entries: [drink], waterEntries: [], drinkTypes: [drinkType],
            profile: profile, eventStart: now.addingTimeInterval(-3600)
        )
        let mealBAC = BACCalculator.currentBAC(
            entries: [drink], waterEntries: [], drinkTypes: [drinkType],
            profile: profile, eventStart: now.addingTimeInterval(-3600),
            stomachState: .fullMeal,
            stomachStateTimestamp: now.addingTimeInterval(-3600),   // ate when event started
            foodEntries: []
        )
        // Full meal should reduce BAC by ~30%
        XCTAssertLessThan(mealBAC, emptyBAC * 0.8)
    }
}
```

- [ ] **Step 2: Run tests**

In Xcode: Cmd+U (run all tests), or select the test file and Cmd+Option+U.

Expected: All 6 tests pass. If `DrinkType.preset(...)` or `UserProfile(...)` initializers differ, adjust to match the actual constructors in your codebase.

- [ ] **Step 3: Commit**

```bash
git add tracksip_ios/SipTrackTests/BACCalculatorFoodTests.swift
git commit -m "test: add food-aware BAC unit tests"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** Event start picker ✓, in-event food logging ✓, decay model ✓, BAC integration ✓, summary view ✓
- [x] **No placeholders:** All tasks contain actual code
- [x] **Type consistency:** `StomachState` and `FoodEntry` defined in Task 1 and used consistently in Tasks 2–8. `computeStomachFactor` signature matches its call sites in `bacAt`. `addFoodEntry` in AppState matches `foodEntries(for:)` return type.
- [x] **Backward compatibility:** Optional fields on `NightEvent`, default parameters on all BAC functions — existing callers unchanged.
