# Drink Avg Time & BAC Spread Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the icon-corruption bug in `EditDrinkView` so that editing a drink type saves the correct internal icon string, which in turn makes `effectiveDrinkingMinutes` resolve correctly and BAC spreading work as intended.

**Architecture:** Two focused changes. (1) Add a `internalIcon(from:)` helper in `EditDrinkView` that translates the SF Symbol name the picker uses back to the internal icon string `DrinkType` expects, and call it in `save()`. (2) Verify `CurrentDrinkCard` in `ActiveEventView` reads `effectiveDrinkingMinutes` from the correct resolved DrinkType — it already does, so this is a read-and-confirm step.

**Tech Stack:** SwiftUI, Swift. No new dependencies.

---

## File Map

| File | Role | Action |
|------|------|--------|
| `SipTrack/Views/Drinks/EditDrinkView.swift` | Drink-type edit form | Add `internalIcon(from:)` helper; call it in `save()` |
| `SipTrack/Views/Event/ActiveEventView.swift` | Active event screen | Confirm `CurrentDrinkCard` reads `effectiveDrinkingMinutes` correctly (no code change expected) |

---

## Background: the bug

`DrinkType.icon` stores internal strings like `"beer-outline"`, `"wine"`, `"flask-outline"`. These drive three switch statements: `sfSymbol`, `color`, and the fallback branch of `effectiveDrinkingMinutes`.

`EditDrinkView` initialises its `icon` state from `existing?.sfSymbol` (an SF Symbol name like `"mug.fill"`). The picker shows and stores SF Symbol names. On `save()`, it writes `icon: icon` — storing `"mug.fill"` into `DrinkType.icon`. All three switch statements then hit their `default` branch: wrong icon displayed, wrong colour, and `effectiveDrinkingMinutes` returns 15 instead of 20/30/1/etc., so the BAC calculator uses the wrong spreading window.

The fix: keep the picker working exactly as-is (sfSymbol names throughout), but translate at the last moment in `save()`.

---

## Task 1 — Add `internalIcon(from:)` helper and fix `save()`

**Files:**
- Modify: `SipTrack/Views/Drinks/EditDrinkView.swift`

- [ ] **Step 1: Open the file and locate `save()`**

In `SipTrack/Views/Drinks/EditDrinkView.swift`, find the `save()` function near the bottom (around line 186). It currently reads:

```swift
private func save() {
    let id   = existing?.id ?? generateId()
    let type = DrinkType(
        id: id,
        name: name,
        defaultVolumeMl: Double(volumeStr) ?? 355,
        defaultAbv: Double(abvStr) ?? 5.0,
        caloriesPerServing: Double(caloriesStr) ?? 150,
        isPreset: existing?.isPreset ?? false,
        icon: icon,
        colorHex: colorHex,
        defaultDrinkingDurationMinutes: Int(durationStr).flatMap { $0 > 0 ? $0 : nil }
    )
    appState.saveDrinkType(type)
    dismiss()
}
```

- [ ] **Step 2: Replace `save()` and add the helper**

Replace the entire `save()` function and add `internalIcon(from:)` immediately after it:

```swift
private func save() {
    let id   = existing?.id ?? generateId()
    let type = DrinkType(
        id: id,
        name: name,
        defaultVolumeMl: Double(volumeStr) ?? 355,
        defaultAbv: Double(abvStr) ?? 5.0,
        caloriesPerServing: Double(caloriesStr) ?? 150,
        isPreset: existing?.isPreset ?? false,
        icon: internalIcon(from: icon),
        colorHex: colorHex,
        defaultDrinkingDurationMinutes: Int(durationStr).flatMap { $0 > 0 ? $0 : nil }
    )
    appState.saveDrinkType(type)
    dismiss()
}

private func internalIcon(from sfSymbol: String) -> String {
    switch sfSymbol {
    case "mug.fill":          return "beer-outline"
    case "wineglass.fill":    return "wine"
    case "wineglass":         return "wine-sharp"
    case "sparkles":          return "sparkles"
    case "flask.fill":        return "flask-outline"
    case "flask":             return "flask"
    case "drop.fill":         return "water"
    case "leaf.fill":         return "leaf"
    case "snowflake":         return "snow"
    case "sun.max.fill":      return "sunny"
    case "fork.knife":        return "restaurant"
    default:                  return "cup"
    }
}
```

- [ ] **Step 3: Build and confirm no errors**

```bash
xcodebuild -scheme siptrack \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected output: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Drinks/EditDrinkView.swift
git commit -m "fix: translate sfSymbol to internal icon on DrinkType save"
```

---

## Task 2 — Confirm `CurrentDrinkCard` resolves correctly

**Files:**
- Read: `SipTrack/Views/Event/ActiveEventView.swift` (lines 410–480)

- [ ] **Step 1: Read `CurrentDrinkCard` and verify the DrinkType lookup**

Open `SipTrack/Views/Event/ActiveEventView.swift` around line 422. The `activeDrink` computed property must look like this:

```swift
private var activeDrink: ActiveDrink? {
    guard let entry = entries.first,
          let dt = drinkTypes.first(where: { $0.id == entry.drinkTypeId })
    else { return nil }
    let total   = dt.effectiveDrinkingMinutes * max(1, entry.quantity)
    let elapsed = now.timeIntervalSince(entry.timestamp) / 60
    guard elapsed >= 0, elapsed < Double(total) else { return nil }
    return ActiveDrink(entry: entry, drinkType: dt, totalMinutes: total, elapsedMinutes: elapsed)
}
```

Confirm:
- `drinkTypes` comes from `appState.allDrinkTypes` (passed in from the parent view at the call site `CurrentDrinkCard(entries: eventEntries, drinkTypes: appState.allDrinkTypes, now: now)`)
- `dt.effectiveDrinkingMinutes` reads `defaultDrinkingDurationMinutes` first — after Task 1's fix, an edited Beer will have `defaultDrinkingDurationMinutes: 20` (or whatever the user set) and `icon: "beer-outline"`, so this resolves correctly

No code change needed if the above matches. If it doesn't match, fix it to match.

- [ ] **Step 2: End-to-end manual verification checklist**

Run the app on a simulator. Follow these steps in order:

1. Go to **Drinks** tab → tap Beer → tap Edit
2. Confirm "Avg. time to finish" field shows **20** (pre-filled from preset)
3. Change it to **2** (2 minutes — makes the curve visible quickly)
4. Tap Save
5. Start a **new event** (end any existing one first so old entries don't pollute BAC)
6. Log one Beer
7. Watch the BAC number — it should read ~0.000 immediately
8. After ~1 minute, BAC should have ticked up slightly
9. After ~2 minutes, the CurrentDrinkCard progress bar should reach 100% and disappear (drink fully absorbed)
10. BAC should now show roughly the beer's peak contribution and start declining

If steps 7–10 behave correctly, the fix is working.

- [ ] **Step 3: Commit any fixes found**

If no changes were needed:

```bash
git commit --allow-empty -m "chore: verify CurrentDrinkCard resolves drinkType correctly"
```

If changes were needed:

```bash
git add SipTrack/Views/Event/ActiveEventView.swift
git commit -m "fix: ensure CurrentDrinkCard reads effectiveDrinkingMinutes from resolved drinkType"
```

---

## Self-Review

**Spec coverage:**
- Section 1 (icon fix) → Task 1 ✓
- Section 2 (avg time field layout) → already in code, confirmed by Task 2 manual check ✓
- Section 3 (CurrentDrinkCard visual) → Task 2 verification ✓

**Placeholder scan:** No TBDs, no vague steps, all code shown in full.

**Type consistency:** `internalIcon(from:)` is defined in Task 1 and used only in Task 1's `save()` — no cross-task type references.
