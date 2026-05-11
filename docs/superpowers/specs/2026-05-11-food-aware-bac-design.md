# Food-Aware BAC Design

**Date:** 2026-05-11
**Status:** Approved

## Overview

SipTrack's BAC calculation currently assumes an empty stomach for every event, making readings pessimistic for users who have eaten. This feature adds food state tracking to the BAC model so readings reflect reality more accurately.

Two components: a stomach-state selector at event start, and a food logging button during the event. No push notifications.

## Architecture

```
Event Creation
  └── StomachState picker (Empty / Snack / Full Meal)
        └── stored on NightEvent as stomachState + stomachStateTimestamp

Active Event
  └── Food log button (same row as Water)
        └── creates FoodEntry(type: snack|meal, timestamp)
        └── stored in NightEvent.foodEntries[]

BAC Engine (BACCalculator.swift)
  └── computeStomachFactor(at: Date, event: NightEvent) → (absorptionDelay: TimeInterval, peakReduction: Double)
        └── considers stomachState + all foodEntries + decay curve
        └── applied per drink at the time it was logged
```

## Data Model Changes

### `NightEvent` additions
```swift
var stomachState: StomachState = .empty        // set at event start
var stomachStateTimestamp: Date = startTime    // when it was set
var foodEntries: [FoodEntry] = []              // logged during event
```

### New types
```swift
enum StomachState: String, Codable {
    case empty, snack, fullMeal
}

struct FoodEntry: Codable, Identifiable {
    var id: UUID
    var type: StomachState   // snack or fullMeal (empty not logged)
    var timestamp: Date
}
```

## BAC Model

### Absorption factors per stomach state

| State     | Peak BAC reduction | Absorption delay |
|-----------|-------------------|-----------------|
| Empty     | 0%                | 0 min           |
| Snack     | −15%              | 15 min          |
| Full Meal | −30%              | 30–45 min       |

### Decay curve

Food's protective effect decays linearly back to `empty` baseline over **2.5 hours** (150 min). This models gastric emptying rate.

```
effectFactor(t) = max(0, 1 - (minutesSinceEating / 150))
peakReduction = basePeakReduction * effectFactor
absorptionDelay = baseAbsorptionDelay * effectFactor
```

### Computing effective stomach factor

At BAC calculation time for each drink:
1. Start with the initial `stomachState` set at event creation
2. Find the most recent `FoodEntry` at or before the drink's timestamp
3. Pick whichever gives the strongest effect (initial state or food entry), apply its decay
4. Apply `peakReduction` and `absorptionDelay` to the Widmark formula for that drink

## UI Changes

### Event creation — stomach state step

Added as the final step before starting an event. Three pill buttons:
- 💨 Empty — Haven't eaten
- 🥨 Snack — Light bite
- 🍽️ Full Meal — Ate properly

Default: `empty` (preserves current behavior for users who skip).

### Active event screen — food logging

New "Food" button alongside the existing "Water" button. Tapping opens a two-option sheet: **Snack** or **Full Meal**. Creates a `FoodEntry` at the current timestamp.

The food card shows current stomach level and approximate time until effect decays (e.g., "Snack level — decays in ~1h 45m").

### Event summary

Food entries listed in the timeline alongside drinks and water. Stomach state shown in the event metadata row.

## Testing Strategy

- Unit tests for `computeStomachFactor` covering: empty baseline, full meal at event start, snack mid-event, decay to zero at 2.5h, multiple food entries (most recent wins)
- Snapshot tests for the stomach state picker and food log sheet
- Integration test: create event with Full Meal state, log 3 drinks, verify BAC is ~30% lower than empty-stomach equivalent

## What This Does Not Change

- The Widmark/Watson formula itself is unchanged
- Hydration adjustment logic is unchanged
- Free tier users get this feature (it directly affects core accuracy, not analytics)
- Watch/widget BAC display automatically benefits since it reads from the same BAC engine
