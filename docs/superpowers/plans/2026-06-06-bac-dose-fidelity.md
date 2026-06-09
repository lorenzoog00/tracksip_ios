# Dose Fidelity (Serving-Size Presets) — Implementation Plan (2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Let users capture the *actual* pour (a double, a pint, a large glass) in one tap, so the BAC model stops under-counting real-world drinks — the dominant cause of "I'm more drunk than it says."

**Architecture:** Pure additive data model — a `ServingSizeOption` (label + mL) per drink category, surfaced as `DrinkType.servingSizeOptions`. Selecting a non-standard size logs a `DrinkEntry` whose existing `volumeOverrideMl` carries the real volume (so the dose math in `calculateAlcohol`/`integrateBAC` needs **zero change**) plus a new display-only `servingSizeLabel`. UI: a `.contextMenu` on each drink tile (tap = standard; long-press = pick a size). Label shown in the timeline.

**Tech Stack:** Swift, SwiftUI, Swift `Testing`.

---

## File Structure

- **Modify:** `SipTrack/Models/DrinkType.swift` — add `ServingSizeOption` + `servingSizeOptions`.
- **Modify:** `SipTrack/Models/NightEvent.swift` — add `DrinkEntry.servingSizeLabel: String?`.
- **Modify:** `SipTrack/State/AppState.swift` — `addDrink` gains `servingSizeLabel`; `projectedBAC` gains `volumeOverrideMl`.
- **Modify:** `SipTrack/Views/Event/DrinkPickerList.swift` — `.contextMenu` of sizes on the tile.
- **Modify:** `SipTrack/Views/Event/ActiveEventView.swift` — sized `handleDrinkTap`.
- **Test:** `siptrackTests/DrinkServingSizeTests.swift` (create).

---

## Task 1: `ServingSizeOption` + `DrinkType.servingSizeOptions`

**Files:**
- Modify: `SipTrack/Models/DrinkType.swift`
- Test: `siptrackTests/DrinkServingSizeTests.swift` (create)

- [ ] **Step 1: Write failing test**

```swift
import Testing
@testable import siptrack

struct DrinkServingSizeTests {

    private func type(_ id: String) -> DrinkType {
        DrinkType.presets.first { $0.id == id }!
    }

    @Test func spirits_offerSingleDoubleTriple() {
        let opts = type("vodka").servingSizeOptions
        #expect(opts.count == 3)
        #expect(opts.contains { $0.label == "Double" && abs($0.volumeMl - 88) < 0.1 })
        #expect(opts.first?.label == "Single")
    }

    @Test func wine_offersSmallStandardLarge() {
        let opts = type("red-wine").servingSizeOptions
        #expect(opts.contains { $0.label == "Large" })
        #expect(opts.contains { $0.label == "Standard" })
    }

    @Test func beer_offersPint() {
        #expect(type("beer").servingSizeOptions.contains { $0.label == "Pint" })
    }

    @Test func standardOption_matchesDefaultVolume() {
        // Every category includes its standard pour = the type's default volume.
        let beer = type("beer")
        #expect(beer.servingSizeOptions.contains { abs($0.volumeMl - beer.defaultVolumeMl) < 0.1 })
    }
}
```

- [ ] **Step 2: Run → FAIL** (`servingSizeOptions` undefined).

- [ ] **Step 3: Implement**

Append to `DrinkType.swift`:

```swift
struct ServingSizeOption: Identifiable, Hashable {
    let label: String
    let volumeMl: Double
    var id: String { label }
}

extension DrinkType {
    // Real-world pour options per category. The "standard" option equals the type's
    // default volume; others capture the common under-counted pours (home double, pint,
    // large wine). Selecting one stores its volume in DrinkEntry.volumeOverrideMl, so the
    // dose math is untouched.
    var servingSizeOptions: [ServingSizeOption] {
        switch drinkCategory {
        case "spirits", "agave":
            return [.init(label: "Single", volumeMl: 44),
                    .init(label: "Double", volumeMl: 88),
                    .init(label: "Triple", volumeMl: 132)]
        case "wine":
            return [.init(label: "Small",    volumeMl: 100),
                    .init(label: "Standard", volumeMl: 150),
                    .init(label: "Large",    volumeMl: 250)]
        case "beer":
            return [.init(label: "Bottle/Can", volumeMl: 355),
                    .init(label: "Pint",       volumeMl: 568),
                    .init(label: "Tallboy",    volumeMl: 473)]
        case "cocktails":
            return [.init(label: "Single", volumeMl: 240),
                    .init(label: "Strong", volumeMl: 360)]
        default:
            return [.init(label: "Standard", volumeMl: defaultVolumeMl),
                    .init(label: "Double",   volumeMl: defaultVolumeMl * 2)]
        }
    }
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(dose): add ServingSizeOption + DrinkType.servingSizeOptions`.

---

## Task 2: `DrinkEntry.servingSizeLabel`

**Files:**
- Modify: `SipTrack/Models/NightEvent.swift`

- [ ] **Step 1: Add the field**

In `struct DrinkEntry`, after `abvOverride`:

```swift
    var abvOverride: Double?
    var servingSizeLabel: String? = nil   // display only; volumeOverrideMl carries the dose
```

(Optional with default → Codable-compatible, existing data and the synthesized memberwise init keep working.)

- [ ] **Step 2: Verify existing tests still compile/pass** (DrinkEntry initializers that omit the label still work because it is defaulted).

Run: `xcodebuild test ... -only-testing:siptrackTests/BACCalculatorCoreTests`
Expected: PASS.

- [ ] **Step 3: Commit** `feat(dose): add DrinkEntry.servingSizeLabel`.

---

## Task 3: Wire `addDrink` + `projectedBAC` for size

**Files:**
- Modify: `SipTrack/State/AppState.swift`

- [ ] **Step 1: Extend `addDrink`**

Add a parameter and store it:

```swift
    func addDrink(
        eventId: String,
        drinkTypeId: String,
        quantity: Int = 1,
        comment: String? = nil,
        volumeOverride: Double? = nil,
        abvOverride: Double? = nil,
        servingSizeLabel: String? = nil
    ) {
        let entry = DrinkEntry(
            id: generateId(),
            eventId: eventId,
            drinkTypeId: drinkTypeId,
            timestamp: Date(),
            quantity: quantity,
            comment: comment,
            volumeOverrideMl: volumeOverride,
            abvOverride: abvOverride,
            servingSizeLabel: servingSizeLabel
        )
```

(Leave the rest of the body unchanged.)

- [ ] **Step 2: Extend `projectedBAC` to accept a volume override**

```swift
    func projectedBAC(forEventId eventId: String, addingDrinkTypeId dtId: String,
                      volumeOverrideMl: Double? = nil) -> Double {
        guard let event = events.first(where: { $0.id == eventId }) else { return 0 }
        let existing    = entries.filter { $0.eventId == eventId }
        let eventWater  = waterEntries.filter { $0.eventId == eventId }
        let eventFood   = foodEntries.filter { $0.eventId == eventId }
        let hypothetical = DrinkEntry(
            id: "__projected__", eventId: eventId, drinkTypeId: dtId, timestamp: Date(),
            quantity: 1, comment: nil, volumeOverrideMl: volumeOverrideMl, abvOverride: nil
        )
        return BACCalculator.currentBAC(
            entries: existing + [hypothetical],
            waterEntries: eventWater, drinkTypes: allDrinkTypes, profile: userProfile,
            eventStart: event.startTime,
            stomachState: event.stomachState ?? .empty,
            stomachStateTimestamp: event.stomachStateTimestamp ?? event.startTime,
            foodEntries: eventFood
        )
    }
```

(Removes the two dead locals `r`/`beta` that were unused.)

- [ ] **Step 3: Commit** `feat(dose): thread serving size through addDrink and projectedBAC`.

---

## Task 4: Tile size menu + sized tap dispatch

**Files:**
- Modify: `SipTrack/Views/Event/DrinkPickerList.swift`
- Modify: `SipTrack/Views/Event/ActiveEventView.swift`

- [ ] **Step 1: Add a sized callback to the picker**

In `DrinkPickerList`, add a second closure and pass it down:

```swift
    let onPick: (DrinkType) -> Void
    let onPickSized: (DrinkType, ServingSizeOption) -> Void
```

Pass `onPickSized` into `pickerSection` → `DrinkTile`. In `DrinkTile`, add:

```swift
    let onPickSized: (ServingSizeOption) -> Void
```

and attach a context menu to the tile's `Button { … } label: { … }` via `.contextMenu`:

```swift
        .contextMenu {
            ForEach(drinkType.servingSizeOptions) { opt in
                Button {
                    onPickSized(opt)
                } label: {
                    Label("\(opt.label) · \(Int(opt.volumeMl)) mL", systemImage: "drop.fill")
                }
            }
        }
```

Wire `onPickSized: { onPickSized(drinkType, $0) }` where `DrinkTile` is constructed in `pickerSection`.

- [ ] **Step 2: Handle the sized pick in `ActiveEventView`**

Where `DrinkPickerList(... onPick: { dt in handleDrinkTap(dt, event: event, bacLimit: bacLimit) })` is constructed, add:

```swift
                onPickSized: { dt, size in
                    handleSizedDrinkTap(dt, size: size, event: event, bacLimit: bacLimit)
                }
```

Add the method next to `handleDrinkTap`:

```swift
    private func handleSizedDrinkTap(_ dt: DrinkType, size: ServingSizeOption,
                                     event: NightEvent, bacLimit: Double) {
        // Standard size → normal path (no label clutter).
        let isStandard = abs(size.volumeMl - dt.defaultVolumeMl) < 0.1
        let label = isStandard ? nil : size.label
        let volume = isStandard ? nil : size.volumeMl
        appState.addDrink(eventId: event.id, drinkTypeId: dt.id,
                          volumeOverride: volume, servingSizeLabel: label)
    }
```

(Sized pours log directly — the threshold-warning sheet stays on the plain tap path; a follow-up can extend it using `projectedBAC(..., volumeOverrideMl:)`.)

- [ ] **Step 3: Build check (device).** SwiftUI `.contextMenu` is additive; confirm the project compiles on macOS.

- [ ] **Step 4: Commit** `feat(dose): serving-size context menu on drink tiles`.

---

## Task 5: Show the size label in the timeline

**Files:**
- Modify: `SipTrack/Views/Event/ActiveEventView.swift` (drink chips / timeline rows) — locate where `DrinkEntry` rows render the drink name; append `· \(label)` when `entry.servingSizeLabel` is set.

- [ ] **Step 1:** Find the timeline/chip view that shows each entry's name (search `servingSizeLabel` is absent; look for where `drinkType.name` renders per entry). Append the label:

```swift
Text(entry.servingSizeLabel.map { "\(name) · \($0)" } ?? name)
```

- [ ] **Step 2: Commit** `feat(dose): show serving-size label in timeline`.

---

## Self-Review

- **Spec coverage:** §3.3 serving-size presets → Tasks 1–5. Dose math untouched (volumeOverrideMl already read by `calculateAlcohol`). ✓
- **Placeholder scan:** Task 5 requires locating the chip view at execution (the only non-literal step) — acceptable; the edit is specified.
- **Type consistency:** `ServingSizeOption(label:volumeMl:)`, `servingSizeOptions`, `servingSizeLabel`, `addDrink(... servingSizeLabel:)`, `projectedBAC(... volumeOverrideMl:)`, `onPickSized` used consistently.
- **Risk:** all changes additive; `DrinkEntry`/`DrinkType` decode old data unchanged. UI is one `.contextMenu` + one closure — low compile risk, but needs a device build to confirm.
