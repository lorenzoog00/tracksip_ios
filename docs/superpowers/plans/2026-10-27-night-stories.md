# Night Stories Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tappable, full-screen story of a night — the user's own photos stamped with the BAC at the moment each was taken, running over their own ceiling line — plus a Pro-gated 15-second video export.

**Architecture:** Every decision lives in pure, testable `Core/` types (`BACPath`, `StoryCeiling`, `StoryFacts`, `PhotoSelection`, `StoryBuilder`, `StoryBeats`); the SwiftUI views and the `AVFoundation` exporter are thin shells over them. Photos are referenced by `PHAsset.localIdentifier` and never copied or uploaded. A single `CGPath`-producing function is shared by the on-screen spine and the exporter so the curve is defined once.

**Tech Stack:** SwiftUI, PhotoKit, AVFoundation + CoreAnimation, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-26-night-stories-design.md`

**Depends on:** `docs/superpowers/plans/2026-10-27-haptics-core.md`. Task 7 calls
`Haptics.shared.play(.storyAdvance(bacDelta:))`, which that plan's Task 3
creates. Land the haptics plan first — it is independent, smaller, and improves
the whole app on its own. If you must run this plan first, drop that one call
and add it back afterwards; nothing else here depends on it.

## Global Constraints

- New test files **must** be added to the `siptrackTests` target in `siptrack.xcodeproj/project.pbxproj` or they never run.
- New tests use Swift Testing (`import Testing`, `struct`, `@Test`, `#expect`), matching `BACCalculatorCoreTests.swift`.
- Build and test require macOS with Xcode. Scheme: `siptrack`.
- **No photo, video or caption may leave the device.** Store `PHAsset.localIdentifier` only — never image bytes — and never sync story state to Firestore.
- Do not change the Firestore document shape. `NightEvent` and `DrinkEntry` gain no fields.
- Minimal is a hard requirement: at most four text elements per card (time, BAC, stage, caption). No stat tiles, badges or icon rows. Only the BAC number may be large. The spine is a hairline — no axes, gridlines or legend.
- Caption cap: 90 characters, single plain line, app-styled. No fonts, colors, sizing or free positioning.
- Export is 1080×1920 H.264 `.mp4`, ~15 s, **no audio track**.
- Copy is hardcoded English; the project has no `.lproj` or `Localizable.strings`.
- `Storage/AppStorage.swift` writes to `.documentDirectory` despite its header comment saying App Group. Use the existing store as-is; do not "fix" the path here.

## Review Focus

- **Night with zero drinks:** `BACCalculator.integrateBAC` returns `[]`, so there is no timeline, no peak and no stage. Every consumer of the timeline must handle empty without dividing by zero or force-unwrapping. Covered in Tasks 1 and 6.
- **Photo taken outside the timeline's range:** the timeline starts at the **first drink**, not `event.startTime`, and runs past `endTime`. `interpolatedBAC` clamps, so a pre-first-drink photo would read as the first sample's value instead of zero. Covered in Task 1.
- **Zero-tolerance driving limit (0.00):** `LegalBACLimit` has many. An unsuppressed line sits on the baseline and is "crossed" by the first sip, making the crossing beat meaningless. Covered in Task 2.
- **Photo permission denied, or Limited Library with nothing in the window:** the story is three synthesized cards; the viewer must still open and say something useful rather than showing an empty stack. Covered in Tasks 5 and 6.
- **Single-moment night (one photo, or none):** segment-bar math and beat distribution both divide by the moment count. Covered in Tasks 6 and 11.

---

## File Map

| File | Action |
|---|---|
| `SipTrack/Core/BACPath.swift` | Create — `bac(at:)` + `CGPath` geometry |
| `SipTrack/Core/StoryCeiling.swift` | Create — ceiling resolution + suppression |
| `SipTrack/Core/StoryFacts.swift` | Create — suggestion catalog |
| `SipTrack/Core/PhotoLibraryService.swift` | Create — PhotoKit query + pure selection |
| `SipTrack/Core/StoryBuilder.swift` | Create — moments assembly, availability |
| `SipTrack/Core/StoryVideoExporter.swift` | Create — beats + AVFoundation export |
| `SipTrack/Models/StoryMoment.swift` | Create — `StoryMoment`, `StoryKind` |
| `SipTrack/Models/NightStoryState.swift` | Create — persisted captions + exclusions |
| `SipTrack/Views/Stories/StoriesView.swift` | Create — viewer shell, tap zones, segments |
| `SipTrack/Views/Stories/StoryCardView.swift` | Create — one card |
| `SipTrack/Views/Stories/StorySpineView.swift` | Create — the hairline curve |
| `SipTrack/Views/Stories/StoryCaptionEditor.swift` | Create — caption + suggestion chip |
| `SipTrack/Views/Stories/StoryEndCardView.swift` | Create — the screenshot target |
| `SipTrack/Views/Stories/StoryCurationGrid.swift` | Create — in-viewer photo removal |
| `SipTrack/Navigation/Route.swift` | Modify — add `case stories(String)` |
| `SipTrack/Views/RootView.swift` | Modify — route destination |
| `SipTrack/Views/Summary/SummaryView.swift` | Modify — primary entry, extract `interpolatedBAC` |
| `SipTrack/Views/Calendar/CalendarView.swift` | Modify — per-night entry |
| `SipTrack/Storage/AppStorage.swift` | Modify — story state store |
| `SipTrack/Info.plist` | Modify — `NSPhotoLibraryUsageDescription` |

Tests: one file per `Core/` type, named `<Type>Tests.swift` in `siptrackTests/`.

---

### Task 1: `BACPath` — BAC at a moment, and the curve

**Files:**
- Create: `SipTrack/Core/BACPath.swift`
- Modify: `SipTrack/Views/Summary/SummaryView.swift:1043` (remove the private `interpolatedBAC` from `SummaryShareCard`, call the new one)
- Test: `siptrackTests/BACPathTests.swift`

**Interfaces:**
- Consumes: `BACDataPoint` (`date: Date`, `bac: Double`)
- Produces:
  - `static func bac(at date: Date, timeline: [BACDataPoint], firstDrink: Date?) -> Double`
  - `static func cgPath(timeline: [BACDataPoint], start: Date, end: Date, size: CGSize, yMax: Double) -> CGPath`

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/BACPathTests.swift`:

```swift
import Testing
import Foundation
import CoreGraphics
@testable import siptrack

struct BACPathTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func pt(_ minutes: Double, _ bac: Double) -> BACDataPoint {
        BACDataPoint(date: t0.addingTimeInterval(minutes * 60), bac: bac)
    }

    // MARK: - bac(at:)

    @Test func bacAt_interpolatesBetweenSamples() {
        let line = [pt(0, 0.00), pt(5, 0.02)]
        let mid = BACPath.bac(at: t0.addingTimeInterval(150), timeline: line, firstDrink: t0)
        #expect(abs(mid - 0.01) < 0.0005)
    }

    @Test func bacAt_beforeFirstDrink_isZeroNotClamped() {
        // The timeline starts at the first drink; a photo taken an hour earlier is 0.000,
        // NOT the first sample's value.
        let firstDrink = t0.addingTimeInterval(3600)
        let line = [BACDataPoint(date: firstDrink, bac: 0.03), BACDataPoint(date: firstDrink.addingTimeInterval(300), bac: 0.05)]
        let early = BACPath.bac(at: t0, timeline: line, firstDrink: firstDrink)
        #expect(early == 0.0)
    }

    @Test func bacAt_afterLastSample_clampsToLast() {
        let line = [pt(0, 0.05), pt(5, 0.04)]
        let late = BACPath.bac(at: t0.addingTimeInterval(9999), timeline: line, firstDrink: t0)
        #expect(abs(late - 0.04) < 0.0005)
    }

    @Test func bacAt_emptyTimeline_isZero() {
        #expect(BACPath.bac(at: t0, timeline: [], firstDrink: nil) == 0.0)
    }

    @Test func bacAt_nilFirstDrink_isZero() {
        // A night with no drinks has no first drink and no curve.
        #expect(BACPath.bac(at: t0, timeline: [], firstDrink: nil) == 0.0)
    }

    // MARK: - cgPath

    @Test func cgPath_emptyTimeline_isEmptyPath() {
        let p = BACPath.cgPath(timeline: [], start: t0, end: t0.addingTimeInterval(3600),
                               size: CGSize(width: 100, height: 50), yMax: 0.2)
        #expect(p.isEmpty)
    }

    @Test func cgPath_staysInsideBounds() {
        let line = [pt(0, 0.0), pt(30, 0.18), pt(60, 0.05)]
        let size = CGSize(width: 200, height: 60)
        let p = BACPath.cgPath(timeline: line, start: t0, end: t0.addingTimeInterval(3600),
                               size: size, yMax: 0.2)
        let box = p.boundingBox
        #expect(box.minX >= -0.5 && box.maxX <= size.width + 0.5)
        #expect(box.minY >= -0.5 && box.maxY <= size.height + 0.5)
    }

    @Test func cgPath_higherBACIsHigherOnScreen() {
        // y grows downward in CoreGraphics; a bigger BAC must map to a smaller y.
        let low  = BACPath.cgPath(timeline: [pt(0, 0.02), pt(60, 0.02)], start: t0, end: t0.addingTimeInterval(3600), size: CGSize(width: 100, height: 50), yMax: 0.2)
        let high = BACPath.cgPath(timeline: [pt(0, 0.18), pt(60, 0.18)], start: t0, end: t0.addingTimeInterval(3600), size: CGSize(width: 100, height: 50), yMax: 0.2)
        #expect(high.boundingBox.midY < low.boundingBox.midY)
    }

    @Test func cgPath_cropsTailPastEventEnd() {
        // The timeline runs until BAC clears, hours past endTime; the spine stops at end.
        let line = [pt(0, 0.05), pt(60, 0.09), pt(600, 0.0)]
        let p = BACPath.cgPath(timeline: line, start: t0, end: t0.addingTimeInterval(3600),
                               size: CGSize(width: 100, height: 50), yMax: 0.2)
        #expect(p.boundingBox.maxX <= 100.5)
    }
}
```

- [ ] **Step 2: Register the test file and run it to verify it fails**

Add `BACPathTests.swift` to the `siptrackTests` target in `project.pbxproj`.

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/BACPathTests`
Expected: FAIL — `cannot find 'BACPath' in scope`

- [ ] **Step 3: Implement `BACPath` in `SipTrack/Core/BACPath.swift`**

Pure Foundation + CoreGraphics. No SwiftUI import — the SwiftUI spine wraps the result in `Path(cgPath:)` and the exporter hands the same `CGPath` to a `CAShapeLayer`, which is the whole point of putting it here.

The timeline is sampled every 300 s, so interpolate linearly between samples and do not smooth beyond that — do not imply precision the model does not have.

- [ ] **Step 4: Run test to verify it passes**

Run the same command.
Expected: PASS, 9 tests.

- [ ] **Step 5: Replace `SummaryShareCard`'s private copy**

Delete `interpolatedBAC(at:sorted:)` from `SummaryView.swift:1043` and call `BACPath.bac(at:timeline:firstDrink:)`. Behaviour there is unchanged except that pre-first-drink times now read 0.000, which is the correct value.

- [ ] **Step 6: Run the full suite and commit**

```bash
xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16'
git add SipTrack/Core/BACPath.swift siptrackTests/BACPathTests.swift SipTrack/Views/Summary/SummaryView.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: add shared BAC path geometry"
```

---

### Task 2: `StoryCeiling` — which line, what label, when none

**Files:**
- Create: `SipTrack/Core/StoryCeiling.swift`
- Test: `siptrackTests/StoryCeilingTests.swift`

**Interfaces:**
- Consumes: `LegalBACLimit`
- Produces:
  - `enum StoryCeilingLabel { case own, driving }`
  - `struct StoryCeiling: Equatable { let value: Double; let label: StoryCeilingLabel; let isDimmed: Bool }`
  - `static func resolve(targetBAC: Double?, eventBACLimit: Double?, legalLimit: Double) -> StoryCeiling?` — `nil` means draw no line

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/StoryCeilingTests.swift`:

```swift
import Testing
@testable import siptrack

struct StoryCeilingTests {

    @Test func resolve_prefersTheUsersOwnCeiling() {
        let c = StoryCeiling.resolve(targetBAC: 0.05, eventBACLimit: nil, legalLimit: 0.08)
        #expect(c?.value == 0.05)
        #expect(c?.label == .own)
        #expect(c?.isDimmed == false)
    }

    @Test func resolve_fallsBackToDrivingLimit() {
        let c = StoryCeiling.resolve(targetBAC: nil, eventBACLimit: 0.08, legalLimit: 0.05)
        #expect(c?.value == 0.08)
        #expect(c?.label == .driving)
    }

    @Test func resolve_withNeitherSet_usesLegalLimitDimmed() {
        // The common night: targetBAC nil, not driving mode.
        let c = StoryCeiling.resolve(targetBAC: nil, eventBACLimit: nil, legalLimit: 0.08)
        #expect(c?.value == 0.08)
        #expect(c?.label == .driving)
        #expect(c?.isDimmed == true)
    }

    @Test func resolve_zeroToleranceLegalLimit_drawsNoLine() {
        #expect(StoryCeiling.resolve(targetBAC: nil, eventBACLimit: nil, legalLimit: 0.0) == nil)
    }

    @Test func resolve_zeroToleranceDrivingMode_drawsNoLine() {
        #expect(StoryCeiling.resolve(targetBAC: nil, eventBACLimit: 0.0, legalLimit: 0.08) == nil)
    }

    @Test func resolve_suppressionThresholdIsFiveTenThousandths() {
        #expect(StoryCeiling.resolve(targetBAC: nil, eventBACLimit: 0.005, legalLimit: 0.08) == nil)
        #expect(StoryCeiling.resolve(targetBAC: nil, eventBACLimit: 0.006, legalLimit: 0.08) != nil)
    }

    @Test func resolve_ownCeilingIsNeverSuppressedByTheLegalLimit() {
        // The user explicitly chose 0.02; a zero-tolerance country must not erase their own goal.
        let c = StoryCeiling.resolve(targetBAC: 0.02, eventBACLimit: nil, legalLimit: 0.0)
        #expect(c?.value == 0.02)
        #expect(c?.label == .own)
    }
}
```

- [ ] **Step 2: Register the test file and run it to verify it fails**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/StoryCeilingTests`
Expected: FAIL — `cannot find 'StoryCeiling' in scope`

- [ ] **Step 3: Implement `StoryCeiling` in `SipTrack/Core/StoryCeiling.swift`**

Suppression threshold is `<= 0.005`, applied to whichever value was selected. `isDimmed` is true only in the third branch, where the user never chose the number.

- [ ] **Step 4: Run test to verify it passes, then commit**

```bash
git add SipTrack/Core/StoryCeiling.swift siptrackTests/StoryCeilingTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: resolve the story's ceiling line"
```

---

### Task 3: `NightStoryState` — captions and exclusions, local only

**Files:**
- Create: `SipTrack/Models/NightStoryState.swift`
- Modify: `SipTrack/Storage/AppStorage.swift`
- Test: `siptrackTests/NightStoryStateTests.swift`

**Interfaces:**
- Produces:
  - `struct NightStoryState: Codable, Equatable { var eventId: String; var excludedAssetIds: Set<String>; var captions: [String: String] }`
  - `mutating func setCaption(_ text: String, for momentId: String)` — trims, drops empty, truncates at 90
  - `DataStore.loadStoryState(eventId:) -> NightStoryState` / `saveStoryState(_:)`

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/NightStoryStateTests.swift`:

```swift
import Testing
import Foundation
@testable import siptrack

struct NightStoryStateTests {

    @Test func newState_hasNoCaptionsAndNoExclusions() {
        let s = NightStoryState(eventId: "e1")
        #expect(s.captions.isEmpty)
        #expect(s.excludedAssetIds.isEmpty)
    }

    @Test func setCaption_storesTrimmedText() {
        var s = NightStoryState(eventId: "e1")
        s.setCaption("  la mejor parte  ", for: "m1")
        #expect(s.captions["m1"] == "la mejor parte")
    }

    @Test func setCaption_emptyOrWhitespace_removesTheCaption() {
        var s = NightStoryState(eventId: "e1")
        s.setCaption("algo", for: "m1")
        s.setCaption("   ", for: "m1")
        #expect(s.captions["m1"] == nil)
    }

    @Test func setCaption_truncatesAtNinetyCharacters() {
        var s = NightStoryState(eventId: "e1")
        s.setCaption(String(repeating: "x", count: 200), for: "m1")
        #expect(s.captions["m1"]?.count == 90)
    }

    @Test func state_roundtripsJSON() throws {
        var s = NightStoryState(eventId: "e1")
        s.setCaption("hola", for: "m1")
        s.excludedAssetIds.insert("asset-9")
        let decoded = try JSONDecoder().decode(NightStoryState.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
    }
}
```

- [ ] **Step 2: Register the test file and run it to verify it fails**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/NightStoryStateTests`
Expected: FAIL

- [ ] **Step 3: Implement the model and the store**

Add a `storyState(eventId:)` key to `AppStorage` following the existing per-key JSON file pattern.

**This type is never pushed to Firestore.** Do not add it to any `FirebaseManager` push or pull path — the identifiers are device-local and the captions belong to photos that only exist on this phone.

- [ ] **Step 4: Run test to verify it passes, then commit**

```bash
git add SipTrack/Models/NightStoryState.swift SipTrack/Storage/AppStorage.swift siptrackTests/NightStoryStateTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: persist story captions and exclusions locally"
```

---

### Task 4: `StoryFacts` — the suggestion catalog

**Files:**
- Create: `SipTrack/Models/StoryMoment.swift`
- Create: `SipTrack/Core/StoryFacts.swift`
- Test: `siptrackTests/StoryFactsTests.swift`

**Interfaces:**
- Consumes: `StoryCeiling` (Task 2)
- Produces:
  - `enum StoryKind: Equatable { case start, photo(assetId: String), peak, end }`
  - `struct StoryMoment: Identifiable, Equatable { let id: String; let kind: StoryKind; let timestamp: Date; let bac: Double; let stageName: String; let isVideo: Bool }` — `id` is the `assetId` for `.photo` and the literal `"start"` / `"peak"` / `"end"` otherwise, so it is a stable caption key across rebuilds
  - `enum StoryFactRule: CaseIterable { case ceilingCrossed, peak, fastestStretch, ceilingMultiple, paceVsBaseline, water, backUnder, soberBy }`
  - `struct StoryFact: Equatable { let text: String; let rule: StoryFactRule }`
  - `struct StoryFactContext { let ceiling: StoryCeiling?; let peakBAC: Double; let peakAt: Date?; let fastestStretchGrams: Double; let baselineGramsPerHour: Double?; let qualifyingBaselineNights: Int; let waterCount: Int; let soberAt: Date? }`
  - `static func suggestion(for moment: StoryMoment, context: StoryFactContext, used: Set<StoryFactRule>) -> StoryFact?`

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/StoryFactsTests.swift` with these tests, using the spec's priority order:

```swift
@Test func suggestion_returnsNilWhenNothingApplies()
@Test func suggestion_neverRepeatsARuleAlreadyUsed()
@Test func suggestion_prefersCeilingCrossedOverPeakOnTheSameMoment()
@Test func suggestion_withNoCeiling_skipsAllCeilingRelativeRules()   // rules 1, 4, 7
@Test func suggestion_paceVsBaseline_skippedUnderThreeQualifyingNights()
@Test func suggestion_ceilingMultiple_formatsOneDecimal()            // 0.118 over 0.05 -> "2.4×"
@Test func suggestion_soberNight_offersNothingBACRelative()
```

Each test builds a `StoryFactContext` inline and asserts on `.rule`, not on exact prose, except `ceilingMultiple` which asserts the `2.4×` substring.

- [ ] **Step 2: Register the test file and run it to verify it fails**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/StoryFactsTests`
Expected: FAIL

- [ ] **Step 3: Implement `StoryFacts` in `SipTrack/Core/StoryFacts.swift`**

Pure function, no SwiftUI, in the shape of the existing `computeNightFacts` in `NightFacts.swift`.

Priority order, first match wins: `ceilingCrossed`, `peak`, `fastestStretch` (most ethanol grams in any rolling 30 min), `ceilingMultiple`, `paceVsBaseline`, `water`, `backUnder`, `soberBy`.

Baseline for `paceVsBaseline`: last 10 finished nights with ≥ 1 drink, compared on ethanol grams per hour; skipped when `qualifyingBaselineNights < 3`.

**Returning `nil` is a normal, common outcome** — it means the caption editor opens with no suggestion chip and the card stays clean. Do not invent filler to avoid it.

Calorie equivalence is **not** here; it belongs to the end card (Task 9).

- [ ] **Step 4: Run test to verify it passes, then commit**

```bash
git add SipTrack/Models/StoryMoment.swift SipTrack/Core/StoryFacts.swift siptrackTests/StoryFactsTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: add story moment model and fact suggestion catalog"
```

---

### Task 5: `PhotoLibraryService` — the query and the selection

**Files:**
- Create: `SipTrack/Core/PhotoLibraryService.swift`
- Modify: `SipTrack/Info.plist`
- Test: `siptrackTests/PhotoSelectionTests.swift`

**Interfaces:**
- Produces:
  - `struct StoryAsset: Equatable, Identifiable { let id: String; let creationDate: Date; let isVideo: Bool }`
  - `enum PhotoSelection { static func cap(_ assets: [StoryAsset], to limit: Int) -> [StoryAsset] }`
  - `final class PhotoLibraryService` with `func authorizationStatus() -> PHAuthorizationStatus`, `func requestAuthorization() async -> PHAuthorizationStatus`, `func assets(from: Date, to: Date) async -> [StoryAsset]`

- [ ] **Step 1: Write the failing test for the pure selection**

Create `siptrackTests/PhotoSelectionTests.swift`:

```swift
@Test func cap_underTheLimit_returnsEverythingInOrder()
@Test func cap_overTheLimit_returnsExactlyTheLimit()
@Test func cap_overTheLimit_keepsFirstAndLast()          // the night's bookends survive
@Test func cap_overTheLimit_spreadsAcrossTheNight()      // not the first N
@Test func cap_emptyInput_returnsEmpty()
@Test func cap_limitOfOne_returnsOne()
```

The spread test builds 60 assets one minute apart and asserts the gap between consecutive kept timestamps never exceeds twice the mean gap — i.e. no clustering.

- [ ] **Step 2: Register the test file and run it to verify it fails**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/PhotoSelectionTests`
Expected: FAIL

- [ ] **Step 3: Implement `PhotoSelection.cap` and `PhotoLibraryService`**

`cap` is pure and testable. The service is not — it talks to PhotoKit — so keep it thin:

- Fetch `PHAsset` with a `creationDate` predicate between the bounds, `mediaType` image **and** video.
- Exclude `PHAssetMediaSubtype.photoScreenshot`.
- Apply `PhotoSelection.cap(_, to: 20)`.
- Request **read** authorization only. Limited Library must work: return whatever assets were granted rather than treating it as denial.

Add `NSPhotoLibraryUsageDescription` to `SipTrack/Info.plist`. The project has none today. Wording must say the photos never leave the phone, because that is true and it raises grant rates.

- [ ] **Step 4: Run test to verify it passes, then commit**

```bash
git add SipTrack/Core/PhotoLibraryService.swift SipTrack/Info.plist siptrackTests/PhotoSelectionTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: query the night's photos from PhotoKit"
```

---

### Task 6: `StoryBuilder` — assembling the moments

**Files:**
- Create: `SipTrack/Core/StoryBuilder.swift`
- Test: `siptrackTests/StoryBuilderTests.swift`

**Interfaces:**
- Consumes: `StoryMoment`, `StoryKind` (Task 4), `BACPath.bac(at:)` (Task 1), `StoryCeiling` (Task 2), `StoryAsset` (Task 5)
- Produces:
  - `static func moments(event: NightEvent, timeline: [BACDataPoint], firstDrink: Date?, assets: [StoryAsset], excluded: Set<String>, ceiling: StoryCeiling?) -> [StoryMoment]`
  - `static func isAvailable(photoCount: Int, drinkCount: Int) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/StoryBuilderTests.swift`:

```swift
@Test func moments_alwaysStartWithStartAndEndWithEnd()
@Test func moments_includesOneCardPerSelectedAsset()
@Test func moments_omitsExcludedAssets()
@Test func moments_ordersChronologically()
@Test func moments_synthesizesPeak_whenNoPhotoIsWithinTenMinutesOfIt()
@Test func moments_omitsSynthesizedPeak_whenAPhotoIsWithinTenMinutes()
@Test func moments_zeroDrinkNight_hasNoPeakAndDoesNotCrash()       // empty timeline
@Test func moments_noPhotos_returnsStartAndEndOnly()
@Test func moments_photoBeforeFirstDrink_readsZeroBAC()
@Test func isAvailable_falseOnlyWhenNoPhotosAndNoDrinks()
```

- [ ] **Step 2: Register the test file and run it to verify it fails**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/StoryBuilderTests`
Expected: FAIL

- [ ] **Step 3: Implement `StoryBuilder`**

A moment's `bac` comes from `BACPath.bac(at:timeline:firstDrink:)` and its `stageName` from `IntoxicationStage.stage(for:).name`.

On a zero-drink night the timeline is `[]` — every moment is BAC 0.000 and there is no peak card. Do not force-unwrap `timeline.max`.

- [ ] **Step 4: Run test to verify it passes, then commit**

```bash
git add SipTrack/Core/StoryBuilder.swift siptrackTests/StoryBuilderTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: assemble a night's story moments"
```

---

### Task 7: The viewer — cards, tap zones, spine

**Files:**
- Create: `SipTrack/Views/Stories/StoriesView.swift`
- Create: `SipTrack/Views/Stories/StoryCardView.swift`
- Create: `SipTrack/Views/Stories/StorySpineView.swift`

**Interfaces:**
- Consumes: `StoryBuilder.moments` (Task 6), `BACPath.cgPath` (Task 1), `StoryCeiling` (Task 2), `NightStoryState` (Task 3), `Haptics.shared.play(.storyAdvance(bacDelta:))` (haptics plan Task 3)
- Produces: `StoriesView(eventId: String)`

- [ ] **Step 1: Build the viewer**

UI task, verified by build plus the device check in Step 3.

- **Tap zones:** left 32% back, right 68% forward. Swipe down dismisses. **No auto-advance** — this is the user's own night and they linger; auto-advance belongs only to the export.
- **Segment bar:** one segment per moment, filled / current / dim. Must not divide by zero on a one-moment story.
- **Card:** full-bleed photo, time top-left, app mark top-right, then kicker, BAC, stage, caption. At most four text elements. Only the BAC is large.
- **Spine:** `Path(cgPath: BACPath.cgPath(...))` pinned to the bottom with a dot at the current moment. A **hairline** — no axes, no gridlines, no legend. One dashed ceiling line, drawn dimmer when `ceiling.isDimmed`, and omitted entirely when `resolve` returned `nil`.
- **Crossing:** when the moment's BAC is at or above a non-nil ceiling and the previous moment's was below, the BAC number is `AppColors.danger` and the stage label reads "you passed your limit".
- **Images:** request a screen-sized thumbnail with `deliveryMode = .opportunistic` and `isNetworkAccessAllowed = true` so a degraded image appears immediately and sharpens. **Playback never waits on the network.** An asset whose identifier no longer resolves falls back to a stage-coloured gradient with no error shown.
- **Videos:** poster frame plus a small play badge; tapping the badge plays the clip muted and looped, in place.
- Controls fade; only the export button and the segment bar persist over the photo.

- [ ] **Step 2: Verify it builds**

Run: `xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify on a device with a real night**

Confirm: tapping advances and goes back; a one-photo night renders; a night with photo access denied still opens; the spine's dot tracks the card.

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Stories/
git commit -m "feat: add the night stories viewer"
```

---

### Task 8: Captions and the suggestion chip

**Files:**
- Create: `SipTrack/Views/Stories/StoryCaptionEditor.swift`
- Modify: `SipTrack/Views/Stories/StoryCardView.swift`

**Interfaces:**
- Consumes: `NightStoryState.setCaption` (Task 3), `StoryFacts.suggestion` (Task 4)

- [ ] **Step 1: Build the editor**

- Tap the lower third of a card → inline text field, keyboard up, type, done.
- **An empty field renders as no caption at all** — not an empty row, not a placeholder.
- 90-character cap enforced in the field as well as in the model.
- Clearable at any time, including after the video has been exported once.
- When `StoryFacts.suggestion` returns a fact for this moment, show it as a dismissible chip above the keyboard; one tap inserts it as ordinary editable text. When it returns `nil`, show no chip.
- **Nothing the app generates is ever written to a card without the user tapping it.**

- [ ] **Step 2: Verify it builds and the state tests still pass**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/NightStoryStateTests`
Expected: PASS

- [ ] **Step 3: Verify on a device that a caption survives leaving and reopening the story**

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Stories/StoryCaptionEditor.swift SipTrack/Views/Stories/StoryCardView.swift
git commit -m "feat: add optional user captions with fact suggestions"
```

---

### Task 9: The end card

**Files:**
- Create: `SipTrack/Views/Stories/StoryEndCardView.swift`

**Interfaces:**
- Consumes: `CalorieEquivalenciesCard`'s existing calorie maths (`SummaryView:651`, `CalFoodCell:733`, `CalSportCell:705`), `StoryCeiling` (Task 2), `NightEvent.aiReport`

- [ ] **Step 1: Build the end card**

Night name, date, duration. Three small stat tiles: drinks, peak, waters. Then **two blocks of equal weight**:

1. The calorie equivalence — reuse the existing computation, do not reimplement it.
2. The honest one — minutes above the ceiling and the time they came back under.

The second block **is not optional and is not smaller than the first.** A recap that only makes a heavy night look aspirational is a problem in App Review and on its own terms. Variants:

- Never crossed → the positive form ("you stayed under your ceiling all night"). This is the night `AppState:334` grades "solid".
- Zero-tolerance country (`StoryCeiling.resolve` returned `nil`) → state the zero limit plainly and report peak and time-to-sober instead of a minutes-above number that would be the whole night.
- Zero-drink night → built around the reset, not the peak.

**The AI line:** when `event.aiReport` is non-nil, show its **first sentence**, extracted client-side. No new report kind, no new Cloud Function call, no new budget — a new `kind` would require a `FREE_LIMITS` entry, a `prompts.js` entry (`buildPrompt` reads `labels.length` and throws on an unknown kind), unpicking the `max_tokens: 700` that `functions/index.js` and `report-policy.js` assert against each other, and a new document type the client's `ReportType` does not decode. When there is no report, show the top `StoryFacts` suggestion instead.

- [ ] **Step 2: Verify it builds, then commit**

```bash
git add SipTrack/Views/Stories/StoryEndCardView.swift
git commit -m "feat: add the story end card"
```

---

### Task 10: In-viewer curation

**Files:**
- Create: `SipTrack/Views/Stories/StoryCurationGrid.swift`

**Interfaces:**
- Consumes: `NightStoryState.excludedAssetIds` (Task 3)

- [ ] **Step 1: Build the grid**

Reachable from a control **inside** the viewer. Grid of the night's assets with everything selected; tapping one removes it; the moment list rebuilds on dismiss.

**Playback starts immediately with everything selected — this grid is never a gate in front of the story.** A mandatory confirmation screen on first open would be a permission prompt, a fetch, thumbnail loads and a tap standing between the user and their night, which is the anti-goal.

- [ ] **Step 2: Verify it builds and an exclusion survives reopening**

- [ ] **Step 3: Commit**

```bash
git add SipTrack/Views/Stories/StoryCurationGrid.swift
git commit -m "feat: let the user remove photos from inside the story"
```

---

### Task 11: The video export

**Files:**
- Create: `SipTrack/Core/StoryVideoExporter.swift`
- Test: `siptrackTests/StoryBeatsTests.swift`

**Interfaces:**
- Consumes: `StoryMoment` (Task 6), `BACPath.cgPath` (Task 1)
- Produces:
  - `enum StoryBeats { static func select(_ moments: [StoryMoment], maxBeats: Int) -> [StoryMoment]; static func durations(for beats: [StoryMoment], total: TimeInterval) -> [TimeInterval] }`
  - `final class StoryVideoExporter { func export(moments: [StoryMoment], state: NightStoryState, ceiling: StoryCeiling?, timeline: [BACDataPoint], progress: @escaping (Double) -> Void) async throws -> URL }`

- [ ] **Step 1: Write the failing test for beat selection**

Create `siptrackTests/StoryBeatsTests.swift`:

```swift
@Test func select_underTheCap_keepsEverything()
@Test func select_overTheCap_alwaysKeepsStartAndEnd()
@Test func select_overTheCap_alwaysKeepsThePeak()
@Test func select_overTheCap_returnsExactlyTheCap()
@Test func select_singleMoment_returnsIt()
@Test func durations_sumToTheTotal()
@Test func durations_givePeakTheLongestHold()
@Test func durations_oneBeat_getsTheWholeTotal()
```

`durations_sumToTheTotal` asserts within 0.01 s of 15.0.

- [ ] **Step 2: Register the test file and run it to verify it fails**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/StoryBeatsTests`
Expected: FAIL

- [ ] **Step 3: Implement `StoryBeats`**

Cap 8 beats. Structural beats always survive: start, ceiling crossing, peak, water, end; the rest are distributed evenly.

Beat lengths from the spec: title 2.4 s, ordinary moments ~2.0 s, crossing 2.1 s, **peak 2.9 s** (the longest hold — it is the climax), relief 1.9 s, end card 2.2 s; scaled to sum to `total`.

- [ ] **Step 4: Run test to verify it passes**

- [ ] **Step 5: Implement `StoryVideoExporter`**

`AVMutableComposition` with a blank video track plus `AVVideoCompositionCoreAnimationTool` driving a `CALayer` tree, exported through `AVAssetExportSession`. 1080×1920, H.264, **no audio track**.

The spine layer is a `CAShapeLayer` whose `path` is `BACPath.cgPath(...)` — the same function the viewer uses — animating `strokeEnd`. The curve is defined once; only the drawing shell differs.

Silent is a decision, not a limitation: commercial music is a copyright strike, and Instagram and TikTok both let the user add a track at upload. The consequence is that cuts cannot land on a beat, so the spine carries the visual pulse and animates continuously rather than cutting per card.

Run off the main queue, report determinate progress, support cancel, write to `FileManager.default.temporaryDirectory`.

Full-resolution assets are needed here, unlike the viewer: fetch with `isNetworkAccessAllowed = true` and fold the download into the progress bar. **Offline with iCloud-optimized storage: refuse with a message naming how many photos need a connection** — do not silently ship a blurry video.

Videos contribute their poster frame, frozen. Real video compositing is a v2 question.

- [ ] **Step 6: Verify on a device that the file plays and uploads to Instagram Stories**

- [ ] **Step 7: Commit**

```bash
git add SipTrack/Core/StoryVideoExporter.swift siptrackTests/StoryBeatsTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "feat: export the night as a 1080x1920 video"
```

---

### Task 12: Entry points, routing and Pro gating

**Files:**
- Modify: `SipTrack/Navigation/Route.swift`
- Modify: `SipTrack/Views/RootView.swift`
- Modify: `SipTrack/Views/Summary/SummaryView.swift`
- Modify: `SipTrack/Views/Calendar/CalendarView.swift`
- Modify: `SipTrack/Views/Stories/StoriesView.swift`

**Interfaces:**
- Consumes: `StoriesView(eventId:)` (Task 7), `StoryVideoExporter` (Task 11), `StoryBuilder.isAvailable` (Task 6)

- [ ] **Step 1: Add the route**

`case stories(String)` in the `Route` enum; destination in `RootView`'s navigation destination switch.

- [ ] **Step 2: Add the two entry points**

- **`SummaryView`** — the main one, a primary action above the existing cards. The label reads **"Create timeline"** the first time for a night (`NightStoryState.generatedAt == nil`) and **"See the timeline"** after. One button, no wizard behind either. Hidden when `StoryBuilder.isAvailable(photoCount:drinkCount:)` is false.
- **`CalendarView`** — tap any past night, go to its story. This entry is **Pro-only by construction**: `CalendarView:51` already gates the whole screen behind `appState.isPro`. That does not make the feature Pro; free users reach the same stories from the summary.

**`HomeView` is deliberately not an entry.** Do not add one.

- [ ] **Step 3: Gate the export, not the viewer**

The viewer is free. On **Export video**, generate and play the result in full inside the app, then raise the paywall at the share step: `showPaywall = true` → `.sheet { ProView(presentation: .modal) }`, matching `CalendarView:57` and `ChallengesView:49`.

The strongest moment to ask is after they have seen their own night cut together and want it, not before.

- [ ] **Step 4: Leave the ads alone**

Do **not** suppress, delay or move `showInterstitialForBrowse` (`SummaryView:428`) or `showInterstitialIfReady` (`ActiveEventView:164`). It is revenue and it is an argument for Pro. The free past-night interstitial is an accepted cost, recorded in the spec.

- [ ] **Step 5: Run the full suite**

Run: `xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: all tests pass.

- [ ] **Step 6: Verify the whole flow on a device**

End a night → summary → "Create timeline" → tap through → write a caption → export → paywall as a free user, share as Pro. Then from the calendar, open an older night.

- [ ] **Step 7: Commit**

```bash
git add SipTrack/Navigation/Route.swift SipTrack/Views/RootView.swift SipTrack/Views/Summary/SummaryView.swift SipTrack/Views/Calendar/CalendarView.swift SipTrack/Views/Stories/StoriesView.swift
git commit -m "feat: wire story entry points and Pro-gate the export"
```
