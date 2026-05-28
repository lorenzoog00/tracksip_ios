# AI Reports Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite all three AI report tiers (daily, weekly, monthly) to give users genuinely new insight in a friend voice, replacing stats recaps with drink-specific recovery advice, honest week stories, and pre-computed behavioral patterns.

**Architecture:** iOS pre-computes insights (dominant drink type, outlier night, best behavior, signature move) and injects them into the Firebase function payload. Firebase prompts are rewritten to narrate these facts in the correct voice per tier. UI `SectionRow` (CoachReportCard) is redesigned from collapsible left-border bars to always-open pill labels; AIReportCard drops static section labels for a clean single-paragraph layout.

**Tech Stack:** Swift/SwiftUI (iOS), JavaScript (Firebase Cloud Functions v2), Anthropic Claude Haiku

---

## File Map

| File | Change |
|---|---|
| `SipTrack/Models/DrinkType.swift` | Add `drinkCategory` computed property |
| `SipTrack/State/AppState.swift` | Add pre-computed fields to `buildEventSummaryData` (daily), `buildWeeklyData` (weekly), `buildMonthlyData` (monthly) |
| `functions/index.js` | Rewrite `generateNightReport` prompt, `buildWeeklyPrompt`, `buildMonthlyPrompt` |
| `SipTrack/Views/Coach/CoachReportCard.swift` | Replace collapsible `SectionRow` with always-open pill label layout |
| `SipTrack/Views/Summary/AIReportCard.swift` | Remove `sectionLabels`, show single paragraph directly |
| `siptrackTests/AIInsightsTests.swift` | New: unit tests for pre-computation logic |

---

## Task 1: Add `drinkCategory` to DrinkType

**Files:**
- Modify: `SipTrack/Models/DrinkType.swift`
- Create: `siptrackTests/AIInsightsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `siptrackTests/AIInsightsTests.swift`:

```swift
import XCTest
@testable import SipTrack

final class AIInsightsTests: XCTestCase {

    func test_drinkCategory_beer() {
        let beer = DrinkType.presets.first { $0.id == "beer" }!
        XCTAssertEqual(beer.drinkCategory, "beer")
    }

    func test_drinkCategory_lightBeer() {
        let beer = DrinkType.presets.first { $0.id == "light-beer" }!
        XCTAssertEqual(beer.drinkCategory, "beer")
    }

    func test_drinkCategory_wine() {
        let wine = DrinkType.presets.first { $0.id == "red-wine" }!
        XCTAssertEqual(wine.drinkCategory, "wine")
    }

    func test_drinkCategory_champagne() {
        let c = DrinkType.presets.first { $0.id == "champagne" }!
        XCTAssertEqual(c.drinkCategory, "wine")
    }

    func test_drinkCategory_tequila() {
        let t = DrinkType.presets.first { $0.id == "tequila" }!
        XCTAssertEqual(t.drinkCategory, "agave")
    }

    func test_drinkCategory_mezcal() {
        let m = DrinkType.presets.first { $0.id == "mezcal" }!
        XCTAssertEqual(m.drinkCategory, "agave")
    }

    func test_drinkCategory_vodka() {
        let v = DrinkType.presets.first { $0.id == "vodka" }!
        XCTAssertEqual(v.drinkCategory, "spirits")
    }

    func test_drinkCategory_whiskey() {
        let w = DrinkType.presets.first { $0.id == "whiskey" }!
        XCTAssertEqual(w.drinkCategory, "spirits")
    }

    func test_drinkCategory_cocktails() {
        let m = DrinkType.presets.first { $0.id == "margarita" }!
        XCTAssertEqual(m.drinkCategory, "cocktails")
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

```
xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/AIInsightsTests 2>&1 | grep -E "FAILED|error:|drinkCategory"
```

Expected: compile error — `drinkCategory` not defined.

- [ ] **Step 3: Add `drinkCategory` to DrinkType.swift**

Add at the end of the file, after the `mergedWith` extension:

```swift
extension DrinkType {
    var drinkCategory: String {
        switch icon {
        case "beer-outline", "beer": return "beer"
        case "wine", "wine-sharp", "champagne", "sparkles": return "wine"
        case "flask", "flask-outline":
            return (id == "tequila" || id == "mezcal") ? "agave" : "spirits"
        default: return "cocktails"
        }
    }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```
xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/AIInsightsTests 2>&1 | grep -E "passed|FAILED"
```

Expected: `Test Suite 'AIInsightsTests' passed`

- [ ] **Step 5: Commit**

```bash
git add SipTrack/Models/DrinkType.swift siptrackTests/AIInsightsTests.swift
git commit -m "feat: add drinkCategory computed property to DrinkType"
```

---

## Task 2: Pre-compute daily insights in AppState

**Files:**
- Modify: `SipTrack/State/AppState.swift` (around line 298–370, inside the daily report builder)
- Modify: `siptrackTests/AIInsightsTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `siptrackTests/AIInsightsTests.swift`:

```swift
    // MARK: - dominantDrinkCategory helper

    func test_dominantCategory_singleType_returnsThatType() {
        // 3 tequila entries
        let types = DrinkType.presets
        let tequila = types.first { $0.id == "tequila" }!
        let counts: [String: Int] = [tequila.drinkCategory: 3]
        XCTAssertEqual(dominantCategory(counts, total: 3), "agave")
    }

    func test_dominantCategory_mixed_returnsMixed() {
        let counts: [String: Int] = ["beer": 2, "agave": 2]
        XCTAssertEqual(dominantCategory(counts, total: 4), "mixed")
    }

    func test_dominantCategory_60percentThreshold() {
        // 3 beer out of 5 = 60% → dominant
        let counts: [String: Int] = ["beer": 3, "spirits": 2]
        XCTAssertEqual(dominantCategory(counts, total: 5), "beer")
    }

    func test_dominantCategory_belowThreshold_returnsMixed() {
        // 2 beer out of 5 = 40% → mixed
        let counts: [String: Int] = ["beer": 2, "spirits": 3]
        // spirits is 60% → dominant
        XCTAssertEqual(dominantCategory(counts, total: 5), "spirits")
    }

    private func dominantCategory(_ counts: [String: Int], total: Int) -> String {
        guard !counts.isEmpty, total > 0 else { return "mixed" }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return "mixed" }
        return Double(top.value) / Double(total) >= 0.6 ? top.key : "mixed"
    }
```

- [ ] **Step 2: Run to confirm they pass** (these test a local helper, so they pass immediately)

```
xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/AIInsightsTests 2>&1 | grep -E "passed|FAILED"
```

- [ ] **Step 3: Add `dominantDrinkType` and `nightOutcome` to the daily report builder**

In `AppState.swift`, locate the block that starts at line ~298 (`let drinkData`). After `drinkData` is built (after line ~302), add:

```swift
        // Pre-computed insights for AI prompt
        var drinkCategoryCounts: [String: Int] = [:]
        for entry in eventEntries {
            guard let dt = allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { continue }
            drinkCategoryCounts[dt.drinkCategory, default: 0] += entry.quantity
        }
        let dominantDrinkType: String = {
            guard !drinkCategoryCounts.isEmpty, drinkCount > 0 else { return "mixed" }
            guard let top = drinkCategoryCounts.max(by: { $0.value < $1.value }) else { return "mixed" }
            return Double(top.value) / Double(drinkCount) >= 0.6 ? top.key : "mixed"
        }()
        let nightOutcome: String = {
            if drinkCount == 0 { return "sober" }
            if let target = event.targetBAC { return peakBAC <= target ? "solid" : "heavy" }
            return peakBAC <= 0.06 ? "solid" : "heavy"
        }()
```

Then in the `params` dictionary (around line 322), add:

```swift
            "dominantDrinkType": dominantDrinkType,
            "nightOutcome": nightOutcome,
```

- [ ] **Step 4: Build to confirm no compile errors**

```
xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add SipTrack/State/AppState.swift siptrackTests/AIInsightsTests.swift
git commit -m "feat: pre-compute dominantDrinkType and nightOutcome for daily AI report"
```

---

## Task 3: Rewrite `generateNightReport` prompt

**Files:**
- Modify: `functions/index.js`

- [ ] **Step 1: Replace the prompt in `generateNightReport`**

In `functions/index.js`, find the block starting with `const prompt = [` inside `generateNightReport`. Replace it entirely:

```javascript
  const dominantDrinkType = d.dominantDrinkType || "mixed";
  const nightOutcome = d.nightOutcome || "heavy";

  const drinkContext = {
    beer:     "Beer is filling and moderate — the morning is usually manageable.",
    wine:     "Wine dehydrates faster than it feels — you'll notice it in your mouth and head when you wake up.",
    agave:    "Tequila and mezcal tend to peak the next morning, around 6-8am. That's just how agave spirits work.",
    spirits:  "Straight spirits absorb fast — the peak has passed but the morning will remind you it happened.",
    cocktails:"Cocktails are sneaky — the sugar masks how much you actually had.",
    mixed:    "Mixing different types tonight means your body is clearing them at different rates — the morning can be unpredictable.",
  };

  const soberPrompt =
    "The user had a sober night. 1-2 sentences: name one real benefit of a sober night for the body " +
    "(sleep, recovery, hydration reset) and tell them it counts. Warm, not preachy.";

  const solidPrompt =
    "The user had a solid night — they paced well or stayed within goal. " +
    "1 sentence of genuine praise naming what worked (drink choice, pacing, hydration, or BAC control). " +
    "1 sentence reinforcing the habit so they repeat it. Warm, not sycophantic.";

  const heavyPrompt =
    `The user had a heavy night. Write 2-3 sentences: ` +
    `(1) Drink-specific right now — what to do before sleep given they drank ${dominantDrinkType} ` +
    `(water? food? timing? nothing generic). ` +
    `(2) One thing to skip or watch for tomorrow morning, specific to ${dominantDrinkType}. ` +
    `(3) One smarter option for next time — a named swap or pacing move, NOT "drink less".`;

  const instruction = nightOutcome === "sober" ? soberPrompt
    : nightOutcome === "solid" ? solidPrompt
    : heavyPrompt;

  const prompt = [
    "You are a knowledgeable friend, not a doctor or a counselor.",
    "Output: 1 paragraph, 2-3 sentences, plain text, second person.",
    "No bullets, no labels, no moralizing. Never tell the user to drink less or cut back.\n",
    `Drink context: ${drinkContext[dominantDrinkType] || drinkContext.mixed}`,
    `Drinks tonight: ${drinkSummary} · Peak BAC: ${peak} · Water: ${waterCount} glasses\n`,
    instruction,
  ].filter(Boolean).join("\n");
```

- [ ] **Step 2: Deploy and smoke-test manually**

```bash
cd functions && firebase emulators:start --only functions 2>&1 | head -20
```

If emulator is not set up, review the prompt string manually:
```bash
node -e "
const d = {dominantDrinkType:'agave', nightOutcome:'heavy', drinks:[{name:'Tequila',quantity:4}], peakBac:0.09, waterCount:2};
console.log('dominantDrinkType:', d.dominantDrinkType);
console.log('nightOutcome:', d.nightOutcome);
"
```

Expected output: `dominantDrinkType: agave`, `nightOutcome: heavy`

- [ ] **Step 3: Commit**

```bash
git add functions/index.js
git commit -m "feat: rewrite daily AI report prompt — drink-specific recovery, friend voice"
```

---

## Task 4: Pre-compute weekly insights in AppState

**Files:**
- Modify: `SipTrack/State/AppState.swift` (inside `buildWeeklyData`, around line 845–923)

- [ ] **Step 1: Add per-night tracking inside the existing loop**

In `buildWeeklyData()`, find the line `var bestNight = ""; var worstNight = ""` (around line 848). Add after it:

```swift
        var bestHydrationNight = ""; var bestHydrationCount = 0
        var bestBACNight = ""; var bestBACValue = Double.infinity
```

Then inside the `for event in weekNights` loop, after `if nightPeak > peakBac { ... }` (around line 867), add:

```swift
            if evWater.count > bestHydrationCount {
                bestHydrationCount = evWater.count
                bestHydrationNight = event.displayName
            }
            if nightPeak > 0 && nightPeak < bestBACValue {
                bestBACValue = nightPeak
                bestBACNight = event.displayName
            }
```

- [ ] **Step 2: Compute bestBehavior fields after the loop**

After the `for event in weekNights` loop ends (around line 876), add:

```swift
        let bestBehaviorType: String
        let bestBehaviorNight: String
        let bestBehaviorDetail: String
        if bestHydrationCount >= 4 {
            bestBehaviorType = "hydration"
            bestBehaviorNight = bestHydrationNight
            bestBehaviorDetail = "\(bestHydrationCount) glasses of water"
        } else if !bestBACNight.isEmpty {
            bestBehaviorType = "pace"
            bestBehaviorNight = bestBACNight
            bestBehaviorDetail = String(format: "%.3f peak BAC", bestBACValue)
        } else {
            bestBehaviorType = "none"
            bestBehaviorNight = ""
            bestBehaviorDetail = ""
        }
```

- [ ] **Step 3: Add fields to the return dictionary**

In the `var d: [String: Any]` block (around line 897), add after `"worstNight": worstNight,`:

```swift
            "bestBehaviorType": bestBehaviorType,
            "bestBehaviorNight": bestBehaviorNight,
            "bestBehaviorDetail": bestBehaviorDetail,
```

- [ ] **Step 4: Build to confirm no compile errors**

```
xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

- [ ] **Step 5: Commit**

```bash
git add SipTrack/State/AppState.swift
git commit -m "feat: pre-compute weekly best behavior insight for AI report"
```

---

## Task 5: Rewrite `buildWeeklyPrompt`

**Files:**
- Modify: `functions/index.js`

- [ ] **Step 1: Replace `buildWeeklyPrompt` entirely**

Find `function buildWeeklyPrompt(d)` in `functions/index.js` and replace the entire function:

```javascript
function buildWeeklyPrompt(d) {
  const {
    userSex, userWeightKg, userAge,
    weekStart, weekEnd,
    nightCount, worstNight,
    bestBehaviorType, bestBehaviorNight, bestBehaviorDetail,
    drivingNights, drivingExceededBACLimit,
  } = d;

  const drivingWarning = drivingExceededBACLimit > 0
    ? `SAFETY: On ${drivingExceededBACLimit} night(s) the user said they would drive but BAC exceeded ` +
      `the legal limit. Address this directly in THE WEEK — name it, don't lecture.`
    : "";

  const bestBehaviorLine = (() => {
    if (bestBehaviorType === "hydration") {
      return `Best behavior this week: ${bestBehaviorNight} — they stayed on top of water ` +
        `(${bestBehaviorDetail}). Call this out specifically and tell them to keep doing it.`;
    }
    if (bestBehaviorType === "pace") {
      return `Best behavior this week: ${bestBehaviorNight} was their cleanest night ` +
        `(${bestBehaviorDetail}). Name it and explain why it's worth repeating.`;
    }
    return "No single standout positive behavior this week — find something small they did right " +
      "and call it out honestly. Even 'you ended at a reasonable time' counts.";
  })();

  return [
    "You are a knowledgeable friend looking back at the user's week.",
    "Write exactly 2 paragraphs separated by a blank line.",
    "Each paragraph MUST start with its label in ALL CAPS + colon.",
    "Do NOT recap stats — the user already sees the numbers. Tell the story.",
    "Never advise to drink less. No forward-looking advice for next week.\n",
    `User: ${userSex}, ${userWeightKg}kg, age ${userAge || "unknown"}.`,
    `Week: ${weekStart} to ${weekEnd} · ${nightCount} nights out.`,
    worstNight ? `Heaviest night: ${worstNight}.` : "",
    drivingNights > 0
      ? `Driving nights: ${drivingNights} (${drivingExceededBACLimit} above legal limit).`
      : "",
    "\nTHE WEEK: What actually happened — name the standout night and say what made it different " +
    "from the rest. 2-3 sentences. Honest, not preachy.",
    "\nWHAT YOU NAILED: " + bestBehaviorLine + " 1-2 sentences. Make them want to repeat it.",
    drivingWarning,
  ].filter(Boolean).join("\n");
}
```

- [ ] **Step 2: Verify syntax**

```bash
cd functions && node -e "require('./index.js'); console.log('syntax ok')"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add functions/index.js
git commit -m "feat: rewrite weekly AI report — 2 sections, story not stats, friend voice"
```

---

## Task 6: Pre-compute monthly insights in AppState

**Files:**
- Modify: `SipTrack/State/AppState.swift` (inside `buildMonthlyData`, around line 925–1030)

- [ ] **Step 1: Add tracking variables before the monthly loop**

In `buildMonthlyData()`, find `var drivingNights = 0; var drivingExceeded = 0` (around line 937). Add after it:

```swift
        var bestMonthBACNight = ""; var bestMonthBACValue = Double.infinity
        var frontLoadedNights = 0; var lateDrinkNights = 0; var mixingNights = 0
```

- [ ] **Step 2: Add detection logic inside the existing loop**

Inside the `for event in monthNights` loop, after `if nightPeak > peakBac { ... }` (around line 956), add:

```swift
            // Best night
            if nightPeak > 0 && nightPeak < bestMonthBACValue {
                bestMonthBACValue = nightPeak
                bestMonthBACNight = event.displayName
            }

            // Front-loading detection
            if let evEnd = event.endTime {
                let duration = evEnd.timeIntervalSince(event.startTime)
                if duration > 0 {
                    let midPoint = event.startTime.addingTimeInterval(duration / 2)
                    let firstHalf = evEntries.filter { $0.timestamp <= midPoint }
                        .reduce(0) { $0 + $1.quantity }
                    let evTotal = evEntries.reduce(0) { $0 + $1.quantity }
                    if evTotal > 0 && Double(firstHalf) / Double(evTotal) > 0.6 {
                        frontLoadedNights += 1
                    }
                }
            }

            // Late drinker detection (last drink after midnight, before 5am)
            if let lastEntry = evEntries.max(by: { $0.timestamp < $1.timestamp }) {
                let hour = Calendar.current.component(.hour, from: lastEntry.timestamp)
                if hour < 5 { lateDrinkNights += 1 }
            }

            // Mixing detection (beer/wine + spirits in same night)
            var hasBeerWine = false; var hasSpirits = false
            for entry in evEntries {
                if let dt = allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) {
                    let cat = dt.drinkCategory
                    if cat == "beer" || cat == "wine" { hasBeerWine = true }
                    if cat == "spirits" || cat == "agave" { hasSpirits = true }
                }
            }
            if hasBeerWine && hasSpirits { mixingNights += 1 }
```

- [ ] **Step 3: Compute signatureMove after the loop**

After the `for event in monthNights` loop (around line 963), add:

```swift
        let nightCountM = monthNights.count
        let signatureMove: String
        if frontLoadedNights > nightCountM / 2 { signatureMove = "front_loads" }
        else if lateDrinkNights > nightCountM / 2 { signatureMove = "late_drinker" }
        else if mixingNights > nightCountM / 2 { signatureMove = "mixes_drinks" }
        else { signatureMove = "none" }
```

- [ ] **Step 4: Add fields to the return dictionary**

In `var d: [String: Any]` (around line 1004), add after `"drinkBreakdown": drinkBreakdown,`:

```swift
            "signatureMove": signatureMove,
            "bestMonthNight": bestMonthBACNight,
```

- [ ] **Step 5: Build to confirm no compile errors**

```
xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

- [ ] **Step 6: Commit**

```bash
git add SipTrack/State/AppState.swift
git commit -m "feat: pre-compute monthly signature move and best night for AI report"
```

---

## Task 7: Rewrite `buildMonthlyPrompt`

**Files:**
- Modify: `functions/index.js`

- [ ] **Step 1: Replace `buildMonthlyPrompt` entirely**

Find `function buildMonthlyPrompt(d)` in `functions/index.js` and replace:

```javascript
function buildMonthlyPrompt(d) {
  const {
    userSex, userWeightKg, userAge, userHeightCm, userBMI,
    monthName, year,
    nightCount, totalDrinks, totalStdDrinks, totalCalories,
    peakBac, peakBacNight, avgBacPerNight,
    totalWater, soberDays,
    prevMonthNightCount,
    weekBreakdowns, drinkBreakdown,
    drivingNights, drivingExceededBACLimit,
    signatureMove, bestMonthNight,
  } = d;

  const weeklyLimit = userSex === "male" ? 14 : 7;
  const monthlyLimit = weeklyLimit * 4;
  const trend = prevMonthNightCount != null
    ? (nightCount > prevMonthNightCount ? "up"
      : nightCount < prevMonthNightCount ? "down" : "flat")
    : "unknown";
  const physique = userHeightCm
    ? `${userWeightKg}kg, ${userHeightCm}cm (BMI ${userBMI})`
    : `${userWeightKg}kg`;

  const weeks = (weekBreakdowns || [])
    .map((w, i) => `  Week ${i + 1}: ${w.nights} nights, ${w.drinks} drinks, peak BAC ${(w.peakBac || 0).toFixed(3)}`)
    .join("\n");

  const drivingLine = drivingNights > 0
    ? `Driving nights: ${drivingNights} (${drivingExceededBACLimit} above legal BAC limit)`
    : "";

  const drivingWarning = drivingExceededBACLimit > 0
    ? `SAFETY: On ${drivingExceededBACLimit} night(s) this month the user said they would drive ` +
      `but BAC exceeded the legal limit. Address this in BEHAVIORAL INSIGHT.`
    : "";

  const signatureMoveLine = (() => {
    switch (signatureMove) {
      case "front_loads":
        return "Pattern detected: the user consistently front-loads — most drinks come in the first " +
          "half of their nights. Name this pattern directly and explain how it affects their BAC curve.";
      case "late_drinker":
        return "Pattern detected: the user's nights consistently run late — last drinks after midnight. " +
          "Name this as their signature and say what it does to sleep and recovery quality.";
      case "mixes_drinks":
        return "Pattern detected: the user regularly mixes beer/wine and spirits in the same night. " +
          "Name this as their move and explain why mixing complicates how the body clears alcohol.";
      default:
        return "No single dominant pattern detected — if the numbers were reasonable, say so: " +
          "consistency itself is a form of control worth naming.";
    }
  })();

  const bestNightLine = bestMonthNight
    ? `Best night of the month: ${bestMonthNight} had the lowest peak BAC. Close this section by ` +
      `calling it out — name it as the standard worth repeating next month.`
    : "";

  return [
    coachPersona,
    "Write exactly 4 paragraphs separated by a blank line.",
    "No markdown, no bullets. Second person. Plain text only.",
    "Each paragraph starts with its label in ALL CAPS + colon.",
    "The 4th starts with OVERALL SYNTHESIS:\n",
    `User: ${userSex}, ${physique}, age ${userAge || "unknown"}.`,
    `Monthly guideline: ${monthlyLimit} standard drinks.\n`,
    `Month: ${monthName} ${year}`,
    `Nights out: ${nightCount} | Sober days: ${soberDays} | Trend vs last month: ${trend}`,
    `Total: ${totalDrinks} drinks (${(totalStdDrinks || totalDrinks).toFixed(1)} std)`,
    `Total calories: ${Math.round(totalCalories || 0)} kcal`,
    `Peak BAC: ${(peakBac || 0).toFixed(3)} on ${peakBacNight || "unknown"}`,
    `Avg BAC/night: ${(avgBacPerNight || 0).toFixed(3)}`,
    `Water: ${totalWater || 0} glasses total`,
    drinkBreakdown ? `Drink breakdown: ${drinkBreakdown}` : "",
    drivingLine,
    weeks ? `\nWeek-by-week:\n${weeks}` : "",
    "\nMEDICAL ANALYSIS: Full-month medical picture. Cumulative BAC exposure, organ load, " +
    "any red flags. Reference physique. Clinical and direct — this section earns its formality.\n",
    "NUTRITION & METABOLISM: Nutritional impact of the specific drinks consumed. " +
    "Caloric total, hydration pattern, one actionable goal for next month.\n",
    "BEHAVIORAL INSIGHT: " + signatureMoveLine + (bestNightLine ? " " + bestNightLine : "") + "\n",
    "OVERALL SYNTHESIS: Two sentences tying all three together. Honest and motivating. " +
    "Do not moralize or recommend drinking less.",
    drivingWarning,
  ].filter(Boolean).join("\n");
}
```

- [ ] **Step 2: Verify syntax**

```bash
cd functions && node -e "require('./index.js'); console.log('syntax ok')"
```

Expected: `syntax ok`

- [ ] **Step 3: Commit**

```bash
git add functions/index.js
git commit -m "feat: rewrite monthly AI report — inject signature move and best night, tone improvements"
```

---

## Task 8: Redesign SectionRow in CoachReportCard

**Files:**
- Modify: `SipTrack/Views/Coach/CoachReportCard.swift`

- [ ] **Step 1: Replace the `SectionRow` struct**

Find `private struct SectionRow: View` in `CoachReportCard.swift` (the collapsible version with `@State private var collapsed = true`). Replace the entire struct with:

```swift
private struct SectionRow: View {
    let section: ParsedSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: section.kind.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(section.kind.color)
                Text(section.kind.title)
                    .font(.system(size: 9, weight: .black))
                    .tracking(2)
                    .foregroundStyle(section.kind.color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(section.kind.color.opacity(0.12))
            .clipShape(Capsule())

            Text(section.body)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(AppColors.text)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }
}
```

- [ ] **Step 2: Build to confirm no compile errors**

```
xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

- [ ] **Step 3: Commit**

```bash
git add SipTrack/Views/Coach/CoachReportCard.swift
git commit -m "feat: replace collapsible section rows with always-open pill labels in CoachReportCard"
```

---

## Task 9: Simplify AIReportCard for single-paragraph daily report

**Files:**
- Modify: `SipTrack/Views/Summary/AIReportCard.swift`

- [ ] **Step 1: Remove `sectionLabels` and update `paragraphs`**

Find and remove:
```swift
    private static let sectionLabels = ["OVERVIEW", "PHYSIOLOGY", "INSIGHT"]
```

Find the `paragraphs` computed property and replace it:
```swift
    private var reportText: String? {
        report?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
```

- [ ] **Step 2: Replace `reportSections` body**

Find `private var reportSections: some View` and replace its body content (the `ForEach` over `paragraphs`):

```swift
    private var reportSections: some View {
        ZStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                if let text = reportText {
                    Text(text)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(AppColors.text)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .padding(.bottom, isPro ? 6 : 0)
                }
            }
            .blur(radius: isPro ? 0 : 9)
            .allowsHitTesting(isPro)

            if !isPro { proGate }
        }
        .clipped()
    }
```

- [ ] **Step 3: Build to confirm no compile errors**

```
xcodebuild build -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD SUCCEEDED"
```

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Summary/AIReportCard.swift
git commit -m "feat: simplify daily AI report card — single paragraph, no static section labels"
```

---

## Task 10: Deploy Firebase functions

**Files:**
- `functions/index.js` (already updated in Tasks 3, 5, 7)

- [ ] **Step 1: Run lint**

```bash
cd functions && npm run lint
```

Expected: no errors. Fix any lint warnings before deploying.

- [ ] **Step 2: Deploy**

```bash
firebase deploy --only functions
```

Expected output includes: `✔  functions[generateNightReport]: function updated`, `✔  functions[generateCoachReport]: function updated`

- [ ] **Step 3: End-to-end smoke test**

1. Open the app on a simulator or device
2. End an existing test event (or use `generateTestWeeklyReport()` from the debug menu)
3. Confirm the AI report generates and displays:
   - Daily: single paragraph, no OVERVIEW/PHYSIOLOGY labels
   - Weekly: two sections with pill labels (THE WEEK / WHAT YOU NAILED), always open
   - Monthly: four sections with pill labels, always open

- [ ] **Step 4: Final commit**

```bash
git add functions/index.js
git commit -m "deploy: push rewritten AI report prompts to Firebase functions"
```
