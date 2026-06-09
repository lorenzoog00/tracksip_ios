# BAC Intelligence — Stats Panel Enhancement

## Goal

Add a "BAC Intelligence" section to `NightStatsSheet` that surfaces deeper BAC insight: where BAC peaked, which direction it's moving right now, and (when driving mode is active) how long until sober and how many minutes above the legal limit.

## Problem

The current stats panel shows pace and duration but doesn't tell the user the most important thing: where their BAC has been and where it's going. Peak BAC, phase (rising vs eliminating), and time-to-sober are all computable from existing data but invisible.

---

## New Section: BAC Intelligence

Inserted between the existing **Pace + Duration tiles** and the **Quick Totals** row.

### 1. Phase badge

A single pill spanning the full width showing which phase the user is in:

| Condition | Label | Color |
|---|---|---|
| Current BAC < peak BAC from 10+ min ago | `▼ Eliminating — BAC dropping` | Green (`#4CD964`) |
| Current BAC within 0.005 of computed peak | `▲ At your peak` | Amber (`#F0A830`) |
| Current BAC still rising (early session, < 30 min in) | `▲ Still absorbing` | Red (`#FF6B6B`) |

### 2. Peak BAC tile + Current BAC tile (side by side)

**Peak BAC tile:**
- Label: `PEAK BAC` (red)
- Value: highest BAC from `bacTimeline()` across the night, formatted `0.XXX`
- Subtitle: time it occurred ("at 11:47 PM")
- If peak hasn't been reached yet (still rising): show `—` and subtitle "still rising"

**Current BAC tile:**
- Label: `CURRENT BAC` (amber)
- Value: `appState.currentBAC(for: eventId)` formatted `0.XXX`
- Subtitle: `↓ 0.XXX from peak` if eliminating, `↑ rising` if still absorbing

### 3. BAC arc bar

A full-width gradient bar showing BAC across the night visually:
- Color gradient: green (0.00) → amber (limit/2) → red (limit) → amber/dropping (post-peak)
- Width represents time elapsed during the event
- A small white vertical marker ticks the peak position on the bar
- Labels below: "start" · "↑ peak" · "now"
- Computed from `BACCalculator.bacTimeline()` — sample at 5-min intervals, normalize peak position to bar width

### 4. Sober in + Above limit tiles (driving mode only)

Only rendered when `event?.drivingMode == true`.

**Sober in tile:**
- Label: `SOBER IN` (blue `#5BC8FF`)
- Value: `BACCalculator.hoursToZeroBAC(currentBAC, profile:)` converted to "Xh YYm"
- Subtitle: estimated clock time ("~ 5:15 AM")

**Above limit tile:**
- Label: `ABOVE LIMIT` (red)
- Value: minutes where BAC exceeded `bacLimit` — computed by scanning `bacTimeline()` for points above the limit, counting 5-min intervals
- Subtitle: "tonight so far"
- Shows `0 min` with green color if never exceeded

---

## Data & Computation

All computed inside `NightStatsSheet` as private properties:

```swift
// Peak BAC + time from bacTimeline()
private var bacTimelinePoints: [BACDataPoint] { ... }
private var peakPoint: BACDataPoint? { bacTimelinePoints.max(by: { $0.bac < $1.bac }) }
private var peakBAC: Double { peakPoint?.bac ?? 0 }
private var peakTime: Date? { peakPoint?.date }

// Phase
private enum BACPhase { case absorbing, atPeak, eliminating }
private var bacPhase: BACPhase { ... }

// Minutes above limit (driving mode only)
private var minutesAboveLimit: Int {
    bacTimelinePoints.filter { $0.bac > bacLimit }.count * 5
}

// Sober time
private var hoursToSober: Double { BACCalculator.hoursToZeroBAC(currentBAC, profile: appState.userProfile) }
```

`BACCalculator.bacTimeline()` already exists and takes: `entries`, `drinkTypes`, `profile`, `eventStart`, `stomachState`, `stomachStateTimestamp`, `foodEntries`. All available from `appState`.

---

## Files to Modify

| File | Change |
|---|---|
| `SipTrack/Views/Event/NightStatsSheet.swift` | Add `bacIntelligenceSection` computed var + supporting private properties |

No other files need to change. All required data is already accessible via `appState`.

---

## What Does NOT Change

- Existing pace/duration tiles — unchanged
- Existing totals row — unchanged
- Existing facts section — unchanged
- Existing timeline — unchanged
- `computeNightFacts()` — unchanged (it already has its own peak BAC logic)

---

## Verification

1. Start an active event, log 3–4 drinks over 30–60 min
2. Open STATS → BAC Intelligence section appears between pace tiles and totals
3. Phase badge shows "Still absorbing" early, switches to "Eliminating" as BAC drops
4. Peak BAC shows the correct peak value with timestamp
5. BAC arc bar renders with peak marker in the right position
6. With driving mode OFF → Sober in + Above limit tiles are hidden
7. With driving mode ON → both tiles appear with correct values
