# Design: Drink Average Time & BAC Spread

**Date:** 2026-05-11  
**Status:** Approved

## Problem

When a user logs a drink, the BAC jumps as if the drink was consumed in one second. The spreading math (`absorbedFraction`) exists and is correct, but two bugs prevent it from working end-to-end:

1. **Icon corruption bug** — `EditDrinkView` initializes `icon` state with `sfSymbol` (e.g. `"mug.fill"`) but `DrinkType.icon` expects the internal icon string (e.g. `"beer-outline"`). After saving an edit, the DrinkType has the wrong icon, breaking all switch-based fallbacks for color, sfSymbol display, and `effectiveDrinkingMinutes`.

2. **Edit field not persisting correctly** — because the icon is corrupted on save, the edited DrinkType no longer maps correctly through `mergedWith`, so BAC spreading uses fallback values or doesn't apply.

3. **Invisible spreading** — even when the math works, the user can't tell because old test entries from previous sessions already contribute a high BAC, masking the gradual rise of the new drink.

## What We Are Building

Three targeted fixes. No new screens, no new models.

---

## Section 1 — Fix the Icon Bug in `EditDrinkView`

**Problem:** `icon` state is set from `existing?.sfSymbol` (an SF Symbol name like `"mug.fill"`) but saved back as `DrinkType.icon` which expects internal strings like `"beer-outline"`.

**Fix:** Add a bidirectional mapping in `EditDrinkView`:
- On `init`: map `existing.icon` (internal) → highlighted sfSymbol in the picker. The picker already uses sfSymbol names, so just initialize `icon` from `existing?.icon` directly, keeping the picker selection in sync by deriving the highlighted symbol from `existing?.sfSymbol`.
- On `save()`: store `icon` as the internal icon string, not the sfSymbol. The picker `iconOptions` array should use internal icon strings as identifiers, displaying via `sfSymbol` lookup.

**Concrete change:** Replace the icon picker so `iconOptions` holds internal icon strings (`"beer-outline"`, `"wine"`, `"flask-outline"`, etc.), and each button displays `Image(systemName: drinkType.sfSymbol(for: option))`. Initialize `_icon` from `existing?.icon ?? "beer-outline"`. Save `icon: icon` directly — now correct.

---

## Section 2 — Edit Form Layout

**"Avg. time to finish (min)"** is the second field in the form, right after Name, above Volume/ABV/Calories. Always visible without scrolling.

- Presets pre-fill from `existing?.effectiveDrinkingMinutes` (e.g. Beer=20, Wine=30, Tequila=1)
- User edits and saves → stored as `defaultDrinkingDurationMinutes` on DrinkType
- Pushed to Firebase via `pushDrinkType` (already handles `drinking_duration_minutes`)
- No other form changes

---

## Section 3 — "Now Absorbing" Visual in Active Event

`CurrentDrinkCard` (the component between BAC hero and stats row) already shows the most recent drink with elapsed/total time and a capsule progress bar. It reads `drinkType.effectiveDrinkingMinutes` for the total duration.

**Fix:** Ensure `CurrentDrinkCard` resolves the drinkType correctly using `appState.allDrinkTypes` (which includes the fixed custom type with correct `defaultDrinkingDurationMinutes`). The BAC hero number ticks up every 5 seconds via the view timer — once icon bug is fixed, the spreading math will use the right T and the number will visibly rise.

No new UI components. The existing card is sufficient.

---

## Data Flow (end-to-end after fix)

```
User edits Beer avg time → 25 min
  → EditDrinkView.save() → DrinkType(icon: "beer-outline", defaultDrinkingDurationMinutes: 25)
  → AppState.saveDrinkType() → customDrinkTypes
  → FirebaseManager.pushDrinkType() → Firestore "drinking_duration_minutes: 25"

User logs Beer
  → DrinkEntry(timestamp: now, drinkTypeId: "beer")
  → allDrinkTypes.first { $0.id == "beer" } → DrinkType with effectiveDrinkingMinutes = 25
  → BACCalculator.bacAt(Date()) → T = 25/60h → absorbedFraction(deltaHours≈0, kA, T) ≈ 0
  → BAC ≈ 0 immediately

5 seconds later
  → timer fires → now = Date() → currentBAC recomputed
  → absorbedFraction(5s/3600, kA, T) ≈ tiny → BAC ticks up slightly

25 minutes later
  → absorbedFraction(0.417h, kA, T) ≈ 57% → BAC at ~half peak

User logs next drink before 25min
  → gap < T → T truncated to gap → first drink's spreading stops early
```

---

## Files Changed

| File | Change |
|------|--------|
| `SipTrack/Views/Drinks/EditDrinkView.swift` | Fix icon picker to use internal strings; keep avg time field as second field |
| `SipTrack/Views/Event/ActiveEventView.swift` | Verify CurrentDrinkCard reads correct effectiveDrinkingMinutes |

`BACCalculator.swift`, `DrinkType.swift`, `AppState.swift`, `FirebaseManager.swift` — **no changes needed**.

---

## Out of Scope

- Changing the spreading math (it's correct)
- Adding a BAC prediction chart
- Clearing old test entries (user should end event and start fresh)
