# Drink Picker Redesign + Stats Panel

## Goal

Make logging a drink as frictionless as possible. Replace the current flat 3-column emoji grid with a searchable, filterable list that puts the user's go-to drinks one tap away. Add a Stats button on the active night screen that shows a live timeline and pace data.

## Problem

The current drink picker is a 3-column grid of all 16+ drinks with no search, no categories, no recents, and no info on each tile. Finding the drink you want requires scrolling and visual scanning. Emojis are used as icons, which looks cheap against the app's premium dark medical aesthetic.

---

## Feature 1 — Drink Picker Redesign

### How it works

The drink picker lives **inline on the active event screen**, replacing the current `QuickAddGrid`. No modal, no extra button. The list is always visible as the user scrolls.

**Tap a row = drink added instantly** (haptic feedback, scale animation). The entire row is the tap target — no separate + button.

### Layout

```
[ Search bar                    ]
[ ♥ Favorites ] [ All ] [ Beer ] [ Wine ] [ Spirits ] [ Cocktail ]

— section label —
[ SF Icon | Drink Name        | ABV · vol · cal  | › ]
[ SF Icon | Drink Name        | ABV · vol · cal  | › ]
```

The chevron `›` on the right is a visual hint that rows are tappable. It does nothing on its own.

### Tabs / filters

| Tab | Shows |
|---|---|
| **♥ Favorites** | Only drinks the user has starred. Default tab if user has any favorites. |
| **All** | Full list. Recents section pinned at top (drinks added this session, most recent first), then all drinks alphabetically. |
| **Beer / Wine / Spirits / Cocktail** | Filtered list for that category. No recents section. |

Search bar filters the currently active tab's list in real time.

### Drink rows

Each row shows:
- **SF Symbol icon** with the drink's existing color on a tinted background pill (already wired up in the codebase via `DrinkType.sfSymbol` and `DrinkType.color`)
- **Name** — 13pt semibold
- **ABV · volume · calories** — 9pt secondary color
- **Subtle chevron** right-aligned

Favorited drinks in the Favorites tab get a slightly warm background tint (`#151a20`, amber border at 20% opacity) to visually distinguish them.

### Recents

Recents are drinks added **during the current session** (the active `NightEvent`), ordered by most recently added. Shown only under the "All" tab, pinned above the full list. Shows timestamp ("added 9:47 PM") as the meta line instead of ABV/vol/cal.

Max 5 recents shown. If none, the "RECENTLY ADDED" section is hidden and the full list starts immediately.

### Interaction on add

1. User taps a drink row
2. Scale animation (0.91x, spring, 0.2s) — existing pattern
3. Haptic (`.medium` impact)
4. Existing BAC limit / driving check runs
5. If over limit → existing `OverLimitWarningSheet`
6. If within limit → drink added, existing toast appears

---

## Feature 2 — Favorites in the Drinks Screen

### What changes in DrinksView

Add a heart toggle button to each drink row in `DrinksView`. Tapping the heart marks that drink as a favorite (persisted in `UserProfile.favoriteDrinkIds: [String]`, synced to Firestore via `pushProfile`).

Add a **filter pill row** at the top of `DrinksView`:

```
[ All ] [ ♥ Favorites ] [ Beer ] [ Wine ] [ Spirits ] [ Cocktail ]
```

- **All** — full list (default)
- **♥ Favorites** — only starred drinks
- **Beer / Wine / Spirits / Cocktail** — category filter

The heart on each row is filled red (`#FF6B6B`) when favorited, empty/dim when not. Tap to toggle.

### Data model

Add to `UserProfile`:

```swift
var favoriteDrinkIds: [String] = []
```

Persisted in Firestore under `profiles/{uid}` as `favorite_drink_ids: [String]`. Synced via existing `pushProfile` / `pullUserData` flow.

### Category assignment

Drink categories are already computed via `DrinkType.drinkCategory` (returns `"beer"`, `"wine"`, `"agave"`, `"spirits"`, `"cocktails"`, `"mixed"`). The picker collapses `"agave"` into the **Spirits** tab for simplicity (tequila/mezcal shown under Spirits).

No new data model changes needed for categories — computed property is sufficient.

---

## Feature 3 — Stats Panel

### Trigger

A compact **STATS** button in the active event screen header, right-aligned next to the event name. Opens a `NightStatsSheet` as a `.sheet` with `.presentationDetents([.large])`. The sheet receives the `eventId` and reads `DrinkEntry` records and water logs from `AppState`.

### Stats sheet content

**Section 1 — How am I going?**
- Title: "How am I going?" with SF Symbol `chart.bar.fill` inline
- Two stat tiles side by side:
  - **PACE** — drinks per hour (total drinks ÷ hours elapsed), formatted to 1 decimal
  - **TIME OUT** — HH:mm since event start, with the start time shown as subtitle

**Section 2 — Quick totals**
Three tiles in a row:
- 🍺 → total drink count (use SF Symbol `mug.fill`)
- 💧 → water count (use SF Symbol `drop.fill`, blue)
- 🔥 → total calories (use SF Symbol `flame.fill`)

**Section 3 — Interesting Facts**

1–3 contextual insight cards generated from the current session data. Each card is a single sentence, styled like a callout chip. Examples:

- "At this pace you'll hit your BAC limit in ~40 min" (pace + current BAC + limit)
- "Your BAC peaked 20 minutes ago — it's dropping now" (peak BAC time vs now)
- "3 tequilas in 90 min — your fastest stretch tonight" (dominant drink + pace spike)
- "You've burned ~620 cal — about the same as a cheeseburger" (calorie comparison)
- "2 waters tonight — on track for solid hydration" (positive reinforcement)
- "This is your heaviest hour of the night so far" (drinks/hr this hour vs average)

Rules for generating facts (computed client-side from session data, no AI call):
- Always show at least 1 fact, max 3
- Priority: safety-relevant first (pace toward limit), then behavioral (peak BAC, fastest stretch), then fun (calorie equivalent)
- If BAC is 0.00 (sober night), show a sober-positive fact instead
- Facts update live as new drinks are added

**Section 4 — Tonight's Timeline**

Chronological list (oldest first) of every `DrinkEntry` and water log for the current event.

**Visual structure per entry:**
- Vertical gradient line on the left connecting all dots (gradient shifts color as BAC rises: green → amber → red)
- Colored dot at the entry's position on the line (color = drink type color)
- Card with a **thin BAC progress bar** at the very top (2px height, spans card width, fills left-to-right proportional to cumulative BAC ÷ 0.08 limit, color gradient: green → amber → red)
- SF Symbol icon (drink's color, tinted background)
- Drink name (left) + cumulative BAC at that moment right-aligned (e.g. "BAC 0.049"), colored by severity
- Time + calories on the second line

**Between entries:** A small time-gap label ("35 min ↓") in muted color shows exactly how long between drinks. This immediately visualizes pacing — clustered entries show a fast stretch, wide gaps show a controlled pace.

**Water entries:** Blue dot, blue card tint, no BAC bar, "Hydration ✓" label instead of BAC.

**Empty state:** "No drinks logged yet — your night starts here." centered in the section.

---

## Files to Modify

| File | Change |
|---|---|
| `SipTrack/Views/Event/ActiveEventView.swift` | Replace `QuickAddGrid` with new `DrinkPickerList`. Add STATS button to header. |
| `SipTrack/Views/Drinks/DrinksView.swift` | Add heart toggle + filter pills |
| `SipTrack/Models/UserProfile.swift` | Add `favoriteDrinkIds: [String]` |
| `SipTrack/State/AppState.swift` | Expose helper: `favoriteDrinkIds`, toggle favorite |
| `Firebase/FirebaseManager.swift` | Persist `favorite_drink_ids` in push/pull |
| New: `SipTrack/Views/Event/DrinkPickerList.swift` | The new inline picker view |
| New: `SipTrack/Views/Event/NightStatsSheet.swift` | The stats panel sheet |

---

## What does NOT change

- `OverLimitWarningSheet` — unchanged, triggered by existing logic
- `EditEntryView` — unchanged
- `NightAnalysisCard` / AI report — unchanged
- The existing toast on drink add — unchanged
- `DrinkType` model — no changes (sfSymbol, color, drinkCategory already computed)

---

## Out of scope

- Reordering favorites
- Custom categories / user-defined tags
- BAC chart / graph in stats (just numbers for now)
- Per-drink quantity selector in the picker (still 1 drink per tap, editable via timeline)
