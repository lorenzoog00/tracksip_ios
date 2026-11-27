# Remove a mistaken drink during the active night — design

Size: small change (short design).

## Intent

Users sometimes log a drink they didn't have (double tap, wrong button). Today
the only fix is the 5-second Undo toast. After that the drink stays in the night
for good and keeps inflating BAC. The user must be able to remove any drink from
the active night at any time, and BAC must then read exactly as if that drink was
never logged: the part already absorbed, the part still in the stomach, and its
effect on elimination all go.

## Goals

- Remove any drink of the **active** night, at any time.
- Before removing, show what changes in BAC terms, based on how far that drink has
  absorbed right now.
- After removal, every BAC consumer agrees: meter, chart, Live Activity / lock
  screen pushes, Watch, shared night, ceiling haptic.

## Non-goals

- Ended nights (summary, friends' feed peak, recovery plan, reports). Later, if ever.
- Editing a drink (type, size, time). `EditEntryView` stays unreachable.
- Undo of a removal. The confirmation is the safety net.
- Removing part of an entry: every tap logs its own entry with quantity 1.
- Cleaning up the dead `TimelineSection` / `TL*Card` code in `ActiveEventView`.

## Anti-goals

- Subtracting a "contribution" from a running BAC by hand. BAC is not a running
  total; any manual subtraction would drift from the model.
- A removal that leaves the deleted drink influencing anything (gulp detection,
  latched ceiling haptic, Watch count).

## Constraints / how the model already behaves

- `BACCalculator.integrateBAC` recomputes the whole curve from the entry list on
  every read. Dropping the entry from `AppState.entries` already removes all its
  alcohol at its current absorption percentage. **No change to the integrator.**
- Gulp detection marks drink *i* as instantly absorbed when drink *i+1* was logged
  inside *i*'s drinking time. Removing a mistaken drink that came right after a real
  one makes the real one absorb gradually again. Decided: keep this (true
  counterfactual: the real drink was never gulped). Consequence: BAC can drop a
  little more than the removed drink's share, then rise back as the real drink
  absorbs. `drinkContributions(excludingId:)` keeps the excluded drink for gulp
  detection on purpose and is **not** the removal semantics.
- Account required to track nights, and the stats sheet only opens from
  `ActiveEventView`.

## Approaches considered

- **A. Remove from the Stats timeline (picked).** "See Timeline" already lists the
  night's drinks with each one's "+0.0xx BAC". Removal sits next to that number. The
  main screen stays as decluttered as `7e7d04f` left it. Cost: two taps away.
- B. Bring a drink list back to the active screen. One tap, but reverses the
  declutter and pushes the picker down on long nights.
- C. Remove only the latest drink from the current-drink card. Simplest, but can't
  fix a mistake that isn't the last drink.

## Design

### UI — `NightStatsSheet` timeline

- `DrinkTimelineCard` gets a visible `⋯` `Menu` with one destructive item,
  "Remove drink", plus the same item on `.contextMenu` (long press). Shown only
  while the event has no `endTime`.
- Choosing it opens a `confirmationDialog`:
  - Title: "Remove <drink name> (<time>)?"
  - Message, line 1: "BAC now: 0.085 → 0.071"
  - Line 2, only while BAC is still heading up (the peak ahead differs by
    ≥ 0.001): "Peak ahead: 0.102 → 0.088"
  - Buttons: "Remove" (destructive), Cancel.
- On confirm: `appState.deleteEntry(id)`, light haptic. The timeline, chart and
  meter re-render from `appState`.

### Model — one new pure function in `BACCalculator`

`removalImpact(removing entryId:, entries:, drinkTypes:, profile:, eventStart:,
stomachState:, stomachStateTimestamp:, foodEntries:, asOf:)` returns
`(nowBefore, nowAfter, peakAheadBefore, peakAheadAfter)`. "After" values are
computed on the entry list **without** the drink (full counterfactual, gulp
re-evaluated). Peak ahead uses the existing `futurePeakBAC`. Unit-tested, and the
test file is registered in `project.pbxproj`.

### State — `AppState.deleteEntry` side effects

Already there: local store, Firestore delete, Live Activity / lock-screen
schedule, shared night sync. Add:

1. `WatchBridge.shared.pushState()`, as `addDrink` does.
2. If `undoEntry?.id == id`: cancel the undo task and clear `undoEntry`, so the toast
   disappears.
3. Clear `activeWarnings`: they were computed with the removed drink.
4. Ceiling latch: if this night's latch is set and the curve so far (event start →
   now) without the drink never reached the ceiling, remove the event id from
   `ceilingCrossedEventIds` and restart the BAC refresh task so its in-memory
   `alreadyFired` re-reads from disk. Update the comments that say the latch
   "never un-latches".

## Left to the builder

- Exact copy and number formatting (3 decimals, like the "+0.0xx BAC" label).
- Whether to log an analytics event, if `Analytics` already has a matching helper.
- Test layout for the latch rule. Prefer a pure predicate next to `HapticSpec`.
