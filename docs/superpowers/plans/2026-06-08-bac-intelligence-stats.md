# BAC Intelligence Stats Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a BAC Intelligence section to NightStatsSheet showing phase badge, peak BAC, current BAC, arc bar, and (in driving mode) sober-in countdown + minutes above limit.

**Architecture:** Single-file change to `NightStatsSheet.swift`. New private computed properties compute the BAC timeline via the existing `BACCalculator.bacTimeline()` call. A new `bacIntelligenceSection` var is inserted between `paceSection` and `totalsSection` in the body. No new files, no new models.

**Tech Stack:** SwiftUI, existing `BACCalculator.bacTimeline()`, `BACDataPoint`, `AppColors`.

---

## File Map

| File | Action |
|---|---|
| `SipTrack/Views/Event/NightStatsSheet.swift` | Add `bacTimelinePoints`, `peakPoint`, `bacPhase` computed props + `bacIntelligenceSection` view + `BACPhase` enum |

---

## Task 1: Add computed properties for BAC Intelligence

**Files:**
- Modify: `SipTrack/Views/Event/NightStatsSheet.swift`

- [ ] **Step 1: Read the file first**

Open `SipTrack/Views/Event/NightStatsSheet.swift` and find the existing `peakBACInfo` property (around line 67). The new properties go immediately below it, before `drinksThisHour`.

- [ ] **Step 2: Add the `BACPhase` enum and timeline properties**

Insert after the closing `}` of `peakBACInfo` (around line 80):

```swift
    // MARK: - BAC Intelligence

    private enum BACPhase { case absorbing, atPeak, eliminating }

    private var bacTimelinePoints: [BACDataPoint] {
        guard let start = event?.startTime, !entries.isEmpty else { return [] }
        return BACCalculator.bacTimeline(
            entries: entries,
            drinkTypes: appState.allDrinkTypes,
            profile: appState.userProfile,
            eventStart: start,
            stomachState: event?.stomachState ?? .empty,
            stomachStateTimestamp: event?.stomachStateTimestamp,
            foodEntries: appState.foodEntries.filter { $0.eventId == eventId }
        )
    }

    private var peakPoint: BACDataPoint? {
        bacTimelinePoints.max(by: { $0.bac < $1.bac })
    }

    private var peakBAC: Double { peakPoint?.bac ?? 0 }
    private var peakTime: Date? { peakPoint?.date }

    private var bacPhase: BACPhase {
        guard peakBAC > 0.001 else { return .absorbing }
        let delta = peakBAC - currentBAC
        if delta <= 0.005 { return .atPeak }
        // Still absorbing if peak occurred very recently (within 20 min) and we're close to it
        if let pt = peakTime, Date().timeIntervalSince(pt) < 1200 && delta < 0.01 { return .atPeak }
        if currentBAC < peakBAC - 0.005 { return .eliminating }
        return .absorbing
    }

    private var minutesAboveLimit: Int {
        // Each bacTimeline point represents 5 minutes
        bacTimelinePoints.filter { $0.bac > bacLimit }.count * 5
    }

    private var hoursToSober: Double {
        BACCalculator.hoursToZeroBAC(currentBAC, profile: appState.userProfile)
    }

    private var peakFraction: Double {
        guard let pt = peakTime, let start = event?.startTime else { return 0 }
        let totalElapsed = max(1, Date().timeIntervalSince(start))
        return min(1.0, pt.timeIntervalSince(start) / totalElapsed)
    }
```

- [ ] **Step 3: Check `appState.foodEntries` property name**

Search `SipTrack/State/AppState.swift` for `foodEntries`:
```bash
grep -n "foodEntries\|var food" /Users/lorenzo.orozco/Developer/siptrack/tracksip_ios/SipTrack/State/AppState.swift | head -5
```

If the property is named differently (e.g. `foodLogs`), update the `bacTimelinePoints` property accordingly.

- [ ] **Step 4: Check `event?.stomachState` and `event?.stomachStateTimestamp` exist on NightEvent**

Verify in `SipTrack/Models/NightEvent.swift` (or wherever NightEvent is defined):
```bash
grep -n "stomachState\|stomachStateTimestamp" /Users/lorenzo.orozco/Developer/siptrack/tracksip_ios/SipTrack/Models/NightEvent.swift 2>/dev/null || grep -rn "stomachState" /Users/lorenzo.orozco/Developer/siptrack/tracksip_ios/SipTrack/Models/ | head -5
```

If `NightEvent` does not have `stomachState`, use `.empty` and `nil` as defaults:
```swift
stomachState: .empty,
stomachStateTimestamp: nil,
```

- [ ] **Step 5: Commit**

```bash
git add SipTrack/Views/Event/NightStatsSheet.swift
git commit -m "feat: add BAC Intelligence computed properties to NightStatsSheet"
```

---

## Task 2: Build the BAC Intelligence section view

**Files:**
- Modify: `SipTrack/Views/Event/NightStatsSheet.swift`

- [ ] **Step 1: Add `bacIntelligenceSection` view**

Find the `// MARK: - Section 1: Pace + Duration` comment in the file. Add the new section view immediately before or after the pace section mark. Add this computed property:

```swift
    // MARK: - BAC Intelligence Section

    private var phaseColor: Color {
        switch bacPhase {
        case .absorbing: return Color(hex: "#FF6B6B")
        case .atPeak:    return Color(hex: "#F0A830")
        case .eliminating: return Color(hex: "#4CD964")
        }
    }

    private var phaseLabel: String {
        switch bacPhase {
        case .absorbing:   return "▲ Still absorbing"
        case .atPeak:      return "▲ At your peak"
        case .eliminating: return "▼ Eliminating — BAC dropping"
        }
    }

    private var bacIntelligenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Phase badge
            HStack {
                Text(phaseLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(phaseColor)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(phaseColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(phaseColor.opacity(0.25), lineWidth: 1))

            // Peak BAC + Current BAC tiles
            HStack(spacing: 10) {
                // Peak
                VStack(alignment: .leading, spacing: 4) {
                    Text("PEAK BAC")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#FF6B6B"))
                    if peakBAC > 0.001 {
                        Text(String(format: "%.3f", peakBAC))
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(hex: "#FF6B6B"))
                        if let pt = peakTime {
                            Text("at \(pt, format: .dateTime.hour().minute())")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 26, weight: .black, design: .monospaced))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("still rising")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#FF6B6B").opacity(0.2), lineWidth: 1))

                // Current
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT BAC")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#F0A830"))
                    Text(String(format: "%.3f", currentBAC))
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundStyle(Color(hex: "#F0A830"))
                    Group {
                        if bacPhase == .eliminating && peakBAC > 0 {
                            Text(String(format: "↓ %.3f from peak", peakBAC - currentBAC))
                        } else {
                            Text("↑ rising")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#F0A830").opacity(0.2), lineWidth: 1))
            }

            // BAC arc bar
            bacArcBar

            // Driving-mode tiles
            if event?.drivingMode == true {
                HStack(spacing: 10) {
                    // Sober in
                    let h = Int(hoursToSober)
                    let m = Int((hoursToSober - Double(h)) * 60)
                    let soberTime = Calendar.current.date(byAdding: .minute, value: Int(hoursToSober * 60), to: Date())

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SOBER IN")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.5)
                            .foregroundStyle(Color(hex: "#5BC8FF"))
                        Text(currentBAC < 0.005 ? "Now" : "\(h)h \(String(format: "%02d", m))m")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundStyle(Color(hex: "#5BC8FF"))
                        if let st = soberTime, currentBAC >= 0.005 {
                            Text("~ \(st, format: .dateTime.hour().minute())")
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#5BC8FF").opacity(0.2), lineWidth: 1))

                    // Above limit
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ABOVE LIMIT")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1.5)
                            .foregroundStyle(minutesAboveLimit > 0 ? Color(hex: "#FF6B6B") : AppColors.textTertiary)
                        Text(minutesAboveLimit > 0 ? "\(minutesAboveLimit) min" : "0 min")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundStyle(minutesAboveLimit > 0 ? Color(hex: "#FF6B6B") : Color(hex: "#4CD964"))
                        Text("tonight so far")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                        minutesAboveLimit > 0 ? Color(hex: "#FF6B6B").opacity(0.2) : AppColors.border,
                        lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var bacArcBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BAC ACROSS THE NIGHT")
                .font(.system(size: 7, weight: .black))
                .tracking(1.5)
                .foregroundStyle(AppColors.textTertiary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(AppColors.border.opacity(0.4))
                        .frame(height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    // Gradient fill up to "now"
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#4CD964"), Color(hex: "#F0A830"), Color(hex: "#FF6B6B"), Color(hex: "#F0A830")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .opacity(bacTimelinePoints.isEmpty ? 0 : 1)

                    // Peak marker
                    if peakBAC > 0.001 && !bacTimelinePoints.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 2, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 1))
                            .offset(x: max(0, min(geo.size.width - 2, geo.size.width * peakFraction - 1)))
                            .offset(y: -3)
                    }
                }
            }
            .frame(height: 8)

            HStack {
                Text("start")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                if peakBAC > 0.001 {
                    Text("↑ peak")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FF6B6B"))
                }
                Spacer()
                Text("now")
                    .font(.system(size: 8))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }
```

**Important:** The `bacIntelligenceSection` body uses `let` bindings (`let h = ...`, `let m = ...`, `let soberTime = ...`) inside a `@ViewBuilder` conditional. To avoid Swift type-check timeout, extract the sober tile to a separate computed var. Replace the inner sober tile with:

```swift
                    soberInTile
```

And add:

```swift
    private var soberInTile: some View {
        let h = Int(hoursToSober)
        let m = Int((hoursToSober - Double(h)) * 60)
        let soberTime = Calendar.current.date(byAdding: .minute, value: Int(hoursToSober * 60), to: Date())
        return VStack(alignment: .leading, spacing: 4) {
            Text("SOBER IN")
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color(hex: "#5BC8FF"))
            Text(currentBAC < 0.005 ? "Now" : "\(h)h \(String(format: "%02d", m))m")
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(Color(hex: "#5BC8FF"))
            if let st = soberTime, currentBAC >= 0.005 {
                Text("~ \(st, format: .dateTime.hour().minute())")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#5BC8FF").opacity(0.2), lineWidth: 1))
    }
```

And remove the inline `let h/m/soberTime` from `bacIntelligenceSection`, replacing the sober tile VStack with just `soberInTile`.

- [ ] **Step 2: Wire `bacIntelligenceSection` into the body**

Find the `body` var in `NightStatsSheet`. Change:
```swift
VStack(spacing: 16) {
    paceSection
    totalsSection
```
to:
```swift
VStack(spacing: 16) {
    paceSection
    bacIntelligenceSection
    totalsSection
```

- [ ] **Step 3: Build (⌘B in Xcode) and fix any compile errors**

Common issues to watch for:
- `appState.foodEntries` — if it doesn't exist, find the correct property name in AppState.swift
- `event?.stomachState` — if NightEvent doesn't have this, use `.empty`
- Any type-check timeout — extract any inline `let` declarations to separate computed vars

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Event/NightStatsSheet.swift
git commit -m "feat: add BAC Intelligence section to NightStatsSheet (phase, peak, arc bar, sober countdown)"
```

---

## Self-Review

- [x] Phase badge: all 3 states defined with correct colors and labels
- [x] Peak BAC: empty state ("—" / "still rising") handled when no peak yet
- [x] Current BAC subtitle: switches between "↓ X from peak" and "↑ rising"
- [x] BAC arc bar: GeometryReader at section level (not in ForEach — safe from type-check issues)
- [x] Driving-mode gate: `event?.drivingMode == true` wraps both bottom tiles
- [x] "Above limit" zero-state: shows "0 min" in green when never exceeded
- [x] Sober tile extracted to `soberInTile` to avoid `let`-in-ViewBuilder type-check issue
- [x] `bacTimelinePoints` guards against empty entries (returns `[]` early)
- [x] No placeholders
