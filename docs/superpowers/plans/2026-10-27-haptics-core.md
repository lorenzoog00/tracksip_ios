# CoreHaptics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's flat `UIFeedbackGenerator` calls with a prepared CoreHaptics engine and purpose-built patterns, and make the ceiling-crossing warning fire once per night instead of every render tick.

**Architecture:** One new `Core/Haptics.swift` wrapping `CHHapticEngine`, with a pure `HapticSpec` layer holding every decision that can be tested without hardware (gating, intensity mapping, crossing edge detection). Existing call sites swap `UIImpactFeedbackGenerator(...)` for `Haptics.shared.play(...)`. Falls back to the current generators when the device has no haptics.

**Tech Stack:** CoreHaptics, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-26-night-stories-design.md` (Part 5)

## Global Constraints

- New test files **must** be added to the `siptrackTests` target in `siptrack.xcodeproj/project.pbxproj` or they never run.
- New tests use Swift Testing (`import Testing`, `struct`, `@Test`, `#expect`), matching `BACCalculatorCoreTests.swift`. Do not add XCTest files.
- Build and test require macOS with Xcode. Scheme: `siptrack`.
- Do not change the Firestore document shape. `FirebaseManager.pushProfile` enumerates profile fields explicitly, so a new local `UserProfile` field is safe.
- Copy is hardcoded English; the project has no `.lproj` or `Localizable.strings`.
- The engine is stopped on background; no pattern may assume it plays while the app is not foreground-active.

## Review Focus

- **Device without haptics** (older hardware, Simulator): `supportsHaptics` is false — every `play` call must be a silent no-op or a generator fallback, never a crash or a thrown error reaching a view. Covered in Task 3.
- **Engine reset mid-session** (`resetHandler` / `stoppedHandler` fire after an audio-session interruption such as a phone call): the next `play` must still work. Covered in Task 3.
- **Ceiling crossed, then dropped below, then crossed again:** must fire exactly once for the whole night, not twice. Covered in Task 2.
- **`targetBAC` nil** (the common night): crossing detection must never fire, and must not treat nil as zero. Covered in Task 2.
- **Cold launch mid-night after a crossing already fired:** must not re-fire. Covered in Task 6.

---

## File Map

| File | Action |
|---|---|
| `SipTrack/Core/HapticSpec.swift` | Create — pure, testable decisions |
| `SipTrack/Core/Haptics.swift` | Create — `CHHapticEngine` wrapper |
| `SipTrack/Models/UserProfile.swift` | Modify — add `hapticsEnabled` |
| `SipTrack/State/AppState.swift` | Modify — crossing edge detection, swap 6 call sites |
| `SipTrack/Views/Event/ActiveEventView.swift` | Modify — swap 1 call site |
| `SipTrack/Views/Event/CreateEventView.swift` | Modify — swap 3 call sites |
| `SipTrack/Views/Event/DrinkPickerList.swift` | Modify — `pour` continuous pattern |
| `SipTrack/Views/Profile/ProfileView.swift` | Modify — haptics toggle |
| `siptrackTests/HapticSpecTests.swift` | Create |
| `siptrackTests/HapticsPreferenceTests.swift` | Create |

---

### Task 1: `hapticsEnabled` preference

**Files:**
- Modify: `SipTrack/Models/UserProfile.swift`
- Modify: `SipTrack/Views/Profile/ProfileView.swift`
- Test: `siptrackTests/HapticsPreferenceTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `UserProfile.hapticsEnabled: Bool` (default `true`)

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/HapticsPreferenceTests.swift`:

```swift
import Testing
import Foundation
@testable import siptrack

struct HapticsPreferenceTests {

    @Test func hapticsEnabled_defaultsToTrue() {
        #expect(UserProfile().hapticsEnabled == true)
    }

    @Test func hapticsEnabled_roundtripsJSON() throws {
        var profile = UserProfile()
        profile.hapticsEnabled = false
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded.hapticsEnabled == false)
    }

    @Test func hapticsEnabled_decodesFromProfileMissingTheKey() throws {
        // Profiles written before this field exists must still decode, defaulting to on.
        let json = #"{"sex":"Male","weightKg":70,"bacLimit":0.08}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(decoded.hapticsEnabled == true)
    }
}
```

- [ ] **Step 2: Register the test file and run it to verify it fails**

Add `HapticsPreferenceTests.swift` to the `siptrackTests` target in `siptrack.xcodeproj/project.pbxproj` (mirror the existing `siptrackTests.swift` entries: one `PBXBuildFile`, one `PBXFileReference`, one entry in the group's `children`, one in the target's `Sources` phase).

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/HapticsPreferenceTests`
Expected: FAIL — `value of type 'UserProfile' has no member 'hapticsEnabled'`

- [ ] **Step 3: Add `var hapticsEnabled: Bool = true` to `UserProfile`**

Place it next to `waterSuggestions`. The third test passes only if the decoder tolerates a missing key — `UserProfile` must already decode partial JSON for this to work; if it does not, give the property a custom `init(from:)` default rather than making it optional.

- [ ] **Step 4: Run test to verify it passes**

Run the same command.
Expected: PASS, 3 tests.

- [ ] **Step 5: Add the toggle to `ProfileView`**

A `Toggle("Haptics", isOn:)` bound through the same path the existing `waterSuggestions` toggle uses, in the same settings section.

- [ ] **Step 6: Commit**

```bash
git add siptrackTests/HapticsPreferenceTests.swift SipTrack/Models/UserProfile.swift SipTrack/Views/Profile/ProfileView.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: add hapticsEnabled preference"
```

---

### Task 2: `HapticSpec` — the testable decisions

**Files:**
- Create: `SipTrack/Core/HapticSpec.swift`
- Test: `siptrackTests/HapticSpecTests.swift`

**Interfaces:**
- Consumes: `UserProfile.hapticsEnabled` (Task 1)
- Produces:
  - `enum HapticPattern { case selection, light, success, warning, storyAdvance(bacDelta: Double), ceilingCrossed, peak, pourEnd, exportDone }`
  - `enum HapticSpec` with:
    - `static func shouldPlay(enabled: Bool, supportsHaptics: Bool) -> Bool`
    - `static func advanceIntensity(bacDelta: Double) -> Float`
    - `static func crossingFires(previousBAC: Double, currentBAC: Double, ceiling: Double?, alreadyFired: Bool) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/HapticSpecTests.swift`:

```swift
import Testing
import Foundation
@testable import siptrack

struct HapticSpecTests {

    // MARK: - shouldPlay

    @Test func shouldPlay_requiresBothEnabledAndSupported() {
        #expect(HapticSpec.shouldPlay(enabled: true,  supportsHaptics: true)  == true)
        #expect(HapticSpec.shouldPlay(enabled: false, supportsHaptics: true)  == false)
        #expect(HapticSpec.shouldPlay(enabled: true,  supportsHaptics: false) == false)
    }

    // MARK: - advanceIntensity

    @Test func advanceIntensity_zeroDelta_isGentle() {
        #expect(HapticSpec.advanceIntensity(bacDelta: 0) <= 0.35)
    }

    @Test func advanceIntensity_risesWithDelta() {
        let small = HapticSpec.advanceIntensity(bacDelta: 0.005)
        let large = HapticSpec.advanceIntensity(bacDelta: 0.040)
        #expect(large > small)
    }

    @Test func advanceIntensity_clampsToUnitRange() {
        #expect(HapticSpec.advanceIntensity(bacDelta: 5.0) <= 1.0)
        #expect(HapticSpec.advanceIntensity(bacDelta: -5.0) >= 0.0)
    }

    @Test func advanceIntensity_usesMagnitudeNotSign() {
        // Going down 0.02 is as notable as going up 0.02.
        #expect(HapticSpec.advanceIntensity(bacDelta: -0.02) == HapticSpec.advanceIntensity(bacDelta: 0.02))
    }

    // MARK: - crossingFires

    @Test func crossingFires_onUpwardCross() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.048, currentBAC: 0.052, ceiling: 0.05, alreadyFired: false) == true)
    }

    @Test func crossingFires_notWhileStayingAbove() {
        // The tick after the crossing must be silent.
        #expect(HapticSpec.crossingFires(previousBAC: 0.052, currentBAC: 0.061, ceiling: 0.05, alreadyFired: true) == false)
    }

    @Test func crossingFires_onlyOncePerNight_evenAfterDroppingBackUnder() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.041, currentBAC: 0.058, ceiling: 0.05, alreadyFired: true) == false)
    }

    @Test func crossingFires_neverWhenNoCeilingSet() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.0, currentBAC: 0.20, ceiling: nil, alreadyFired: false) == false)
    }

    @Test func crossingFires_notWhenAlreadyAboveAtFirstObservation() {
        // previous == current happens on the first tick after a cold launch.
        #expect(HapticSpec.crossingFires(previousBAC: 0.09, currentBAC: 0.09, ceiling: 0.05, alreadyFired: false) == false)
    }

    @Test func crossingFires_notOnDownwardCross() {
        #expect(HapticSpec.crossingFires(previousBAC: 0.061, currentBAC: 0.044, ceiling: 0.05, alreadyFired: false) == false)
    }
}
```

- [ ] **Step 2: Register the test file and run it to verify it fails**

Add `HapticSpecTests.swift` to the `siptrackTests` target in `project.pbxproj`.

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/HapticSpecTests`
Expected: FAIL — `cannot find 'HapticSpec' in scope`

- [ ] **Step 3: Implement `HapticPattern` and `HapticSpec` in `SipTrack/Core/HapticSpec.swift`**

Pure Foundation only — no CoreHaptics import, no SwiftUI, so the suite runs without hardware.

`crossingFires` is a strict upward edge: requires a non-nil ceiling, `previousBAC < ceiling`, `currentBAC >= ceiling`, and `alreadyFired == false`.

`advanceIntensity` maps `abs(bacDelta)` over `0...0.04` onto `0.2...0.9`, clamped.

- [ ] **Step 4: Run test to verify it passes**

Run the same command.
Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add siptrackTests/HapticSpecTests.swift SipTrack/Core/HapticSpec.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: add pure haptic decision layer"
```

---

### Task 3: The `Haptics` engine

**Files:**
- Create: `SipTrack/Core/Haptics.swift`

**Interfaces:**
- Consumes: `HapticPattern`, `HapticSpec.shouldPlay`, `HapticSpec.advanceIntensity` (Task 2); `UserProfile.hapticsEnabled` (Task 1)
- Produces:
  - `final class Haptics` with `static let shared: Haptics`
  - `func prepare()` — starts the engine; safe to call repeatedly
  - `func play(_ pattern: HapticPattern)`
  - `func beginContinuous(initialIntensity: Float)` / `func updateContinuous(intensity: Float)` / `func endContinuous(withTransient: Bool)`
  - `func stop()` — called on background

- [ ] **Step 1: Implement `Haptics` in `SipTrack/Core/Haptics.swift`**

No unit test: `CHHapticEngine` needs hardware and the Simulator reports `supportsHaptics == false`. Task 2 covers every branch that is decidable without a device; this task is the thin shell over the framework. It is verified by Step 2 and on-device in Step 3.

Requirements:

- Reads `supportsHaptics` from `CHHapticEngine.capabilitiesForHardware()` once and caches it.
- Reads `hapticsEnabled` from `DataStore.shared.loadUserProfile()`; gate every entry point through `HapticSpec.shouldPlay`.
- When `shouldPlay` is false, `play` falls back to the matching `UIFeedbackGenerator` (`selection` → `UISelectionFeedbackGenerator`, `light` → `.light` impact, `success`/`warning` → `UINotificationFeedbackGenerator`) and the story/pour patterns become no-ops. **Never throws out of `play`.**
- `prepare()` calls `engine.start()` and is idempotent; call it before a gesture, not during it.
- Sets `engine.stoppedHandler` and `engine.resetHandler` to mark the engine dead and restart lazily on the next `play`, so a phone-call interruption does not kill haptics for the rest of the night.
- Pattern shapes: `ceilingCrossed` is two `.hapticTransient` events 0.12 s apart at sharpness 0.9; `peak` is one `.hapticContinuous` of 0.25 s with an intensity control curve ramping 0.3 → 1.0; `storyAdvance` is one transient whose intensity is `HapticSpec.advanceIntensity(bacDelta:)`; `pourEnd` is one sharp transient; `exportDone` maps to `success`.

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify on a device**

On a physical iPhone, call `Haptics.shared.play(.ceilingCrossed)` from a temporary debug button. Confirm two distinct taps, then remove the button. The Simulator cannot verify this.

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Core/Haptics.swift
git commit -m "feat: add CoreHaptics engine wrapper"
```

---

### Task 4: Replace the existing call sites

**Files:**
- Modify: `SipTrack/State/AppState.swift` (lines 193, 267, 1273, 1301, 1320, 1333)
- Modify: `SipTrack/Views/Event/ActiveEventView.swift:272`
- Modify: `SipTrack/Views/Event/CreateEventView.swift` (lines 349, 374, 394)
- Modify: `SipTrack/SipTrackApp.swift`

**Interfaces:**
- Consumes: `Haptics.shared.play`, `prepare`, `stop` (Task 3)
- Produces: nothing new

- [ ] **Step 1: Swap each generator call for its pattern**

| Site | Was | Becomes |
|---|---|---|
| `AppState:193`, `AppState:1273` | `.medium` impact | `Haptics.shared.play(.light)` |
| `AppState:267` | `.success` notification | `.play(.success)` |
| `AppState:1301`, `:1320`, `:1333` | `.light` impact | `.play(.light)` |
| `ActiveEventView:272` | `.warning` notification | `.play(.warning)` |
| `CreateEventView:349` | selection changed | `.play(.selection)` |
| `CreateEventView:374`, `:394` | `.light` impact | `.play(.light)` |

- [ ] **Step 2: Add lifecycle hooks in `SipTrackApp.swift`**

Call `Haptics.shared.prepare()` where `AdManager.shared.showAppOpenAdIfReady` is called on becoming active (line ~52), and `Haptics.shared.stop()` on `.background`.

- [ ] **Step 3: Verify it builds and the whole suite still passes**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add SipTrack/State/AppState.swift SipTrack/Views/Event/ActiveEventView.swift SipTrack/Views/Event/CreateEventView.swift SipTrack/SipTrackApp.swift
git commit -m "refactor: route existing haptics through Haptics engine"
```

---

### Task 5: The `pour` pattern

**Files:**
- Modify: `SipTrack/Views/Event/DrinkPickerList.swift` (the `haptic` property at :244, the `prepare()` at :301)

**Interfaces:**
- Consumes: `Haptics.shared.beginContinuous/updateContinuous/endContinuous` (Task 3)

- [ ] **Step 1: Replace the stored generator with a long-press gesture**

Delete `private let haptic = UIImpactFeedbackGenerator(style: .medium)` at :244 and the `haptic.prepare()` at :301; replace the latter with `Haptics.shared.prepare()`.

Attach a `DragGesture(minimumDistance: 0)` to the drink tile: on first change call `beginContinuous(initialIntensity: 0.25)`, then `updateContinuous` on a ramp to 0.8 over 0.6 s, and on end call `endContinuous(withTransient: true)`.

This site was already prepared, so it is not a latency fix — a flat `.medium` impact is the wrong *shape* for pouring. The tap-to-add behaviour must keep working unchanged for a quick tap.

- [ ] **Step 2: Verify the existing drink-picker tests still pass**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/NightPickerTests -only-testing:siptrackTests/DrinkServingSizeTests`
Expected: PASS

- [ ] **Step 3: Verify on a device that a quick tap still logs one drink**

A drag gesture with `minimumDistance: 0` can swallow taps. Confirm tap-to-add and scroll-past-a-tile both still work before committing.

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Event/DrinkPickerList.swift
git commit -m "feat: add continuous pour haptic to the drink picker"
```

---

### Task 6: Ceiling-crossed, once per night

**Files:**
- Modify: `SipTrack/State/AppState.swift`
- Test: `siptrackTests/HapticSpecTests.swift` (extend)

**Interfaces:**
- Consumes: `HapticSpec.crossingFires` (Task 2), `Haptics.shared.play(.ceilingCrossed)` (Task 3)
- Produces: `AppState.hasFiredCeilingCrossing(eventId: String) -> Bool`, persisted across launches

- [ ] **Step 1: Write the failing test for persistence**

Append to `siptrackTests/HapticSpecTests.swift`:

```swift
    @Test func crossedEventIds_roundtripsJSON() throws {
        let ids: Set<String> = ["evt-1", "evt-2"]
        let data = try JSONEncoder().encode(ids)
        let decoded = try JSONDecoder().decode(Set<String>.self, from: data)
        #expect(decoded == ids)
    }
```

- [ ] **Step 2: Run it to verify it fails or passes trivially, then implement**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/HapticSpecTests`

- [ ] **Step 3: Add edge detection to the BAC tick in `AppState`**

`ActiveEventView:61` is a **view-render predicate**, not a detector, and `startBACRefreshTimer` ticks every 10 s — firing a haptic from that view would buzz every 10 seconds all night. Detection belongs in the tick.

In the refresh timer's body, for the active event:

1. Resolve the ceiling: `event.targetBAC ?? event.bacLimit` (nil when neither is set — do **not** substitute a legal limit here; this is the user's own ceiling, and the spec's legal-limit fallback is a display concern for the stories spine only).
2. Call `HapticSpec.crossingFires(previousBAC:currentBAC:ceiling:alreadyFired:)` with the BAC from the previous tick.
3. On `true`: `Haptics.shared.play(.ceilingCrossed)` and record the event id in a persisted `Set<String>` through the existing `AppStorage` JSON store.

Store the crossed ids locally only. Do **not** add a field to `NightEvent` — that struct syncs to Firestore and the constraint above forbids changing its shape.

- [ ] **Step 4: Run the full suite**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: all tests pass.

- [ ] **Step 5: Verify once-per-night on a device**

Set a ceiling of 0.02, log a drink, confirm exactly one double-tap when the curve crosses, and confirm no further buzz for the rest of the session. Force-quit and relaunch mid-night: confirm it does not fire again.

- [ ] **Step 6: Commit**

```bash
git add SipTrack/State/AppState.swift siptrackTests/HapticSpecTests.swift
git commit -m "feat: fire ceiling-crossed haptic once per night"
```

---

## Out of scope

The pocket case — feeling the crossing while the phone is away — is **not** solvable with haptics: they do not play when the app is not foreground-active, and Task 4 stops the engine on background. That needs a local notification, modelled on `WaterReminderManager`. Deliberately excluded so this plan stays small and shippable.
