# BAC Accuracy Overhaul — Design

**Date:** 2026-06-06
**Status:** Approved for planning
**Trigger:** User reported the app under-registers intoxication — "it told me I was able to drive and I clearly was not," and "I am feeling much more drunk" than the number shows. Wants water, time, food, and the formula re-examined and made as accurate as possible.

---

## 1. Problem & Diagnosis

The complaint is **under-prediction of the displayed BAC and a false "OK to drive" signal.** A full audit of `BACCalculator.swift` against the primary pharmacokinetics literature (see `.planning/research/BAC-ACCURACY-RESEARCH.md` and sources in §8) found that the core math is sound and, if anything, Widmark-class formulas *over*-estimate — so the fix is **not** to inflate the math. The levers that matter: **dose input** and the **elimination tail** move the level; **absorption-rate calibration** fixes the shape and timing of the rising limb and the peak; and the **verdict** governs the drive call:

| Lever | Audit verdict | Action |
|---|---|---|
| **Water** | Already inert. `applyHydration` returns BAC unchanged; hydration is coaching-only. Correct per literature. | No model change. Audit UI copy for any "water lowers BAC" implication; remove if found. |
| **Food / first-pass metabolism** | Already calibrated. Fed FPM ≈ 20% of dose (Toxics 2023); code already uses 20% full meal / 10% snack / 0% empty. Default state is `.empty`, so food only ever lowers BAC when explicitly logged. | No change. (Earlier suspicion of over-aggressiveness was wrong.) |
| **Absorption rate `kA` / peak timing** | **Defect.** Current empty-stomach `kA = 6/h` (t½ ≈ 7 min) is an *intestinal* constant, but gastric emptying is rate-limiting, so the effective combined constant is slower. Result: the model peaks at ~30 min when the real Tmax is 36–60 min, and a single fast `kA` ignores that beer/wine peak **lower and later** than spirits for the *same grams* (Mitchell 2014). Because elimination runs concurrently with absorption, `kA` affects peak *height*, not just timing. | **Calibrate `kA` to beverage strength (%ABV) against Mitchell Tmax/Cmax.** Keep the gulp instant-absorption UX for rapid logging. |
| **Time / elimination** | **Defect.** Zero-order `β·t` clears in a straight line to zero. Real elimination is Michaelis–Menten and slows below ~0.02 g/100mL → the linear model declares the user sober / under-limit **too early**. This is the descending-limb cause of the false "you can drive." | **Switch to Michaelis–Menten elimination via forward integration.** |
| **Dose input** | **Dominant defect.** Vd and the formula are correct, so the only way the number comes out low is too few grams in. Presets are exact NIAAA standard servings; real pours run 30–50% larger and home spirits are routinely doubles. Logging "1 vodka" while pouring a double counts half the alcohol. | **Add full per-category serving-size presets.** |
| **Safety verdict** | **Defect.** "DO NOT DRIVE" only appears at/above the legal limit; below it the app shows nothing, which reads as permission. The legal limit is a prosecution line, not a safety line (impairment from 0.02, marked by 0.05). | **Reframe: never affirm drive-safety; impairment band below the legal limit; verdict off the conservative upper edge + rising-limb projection + the longer M-M tail.** |

**Honest caveat carried into the app:** even with all fixes, subjective drunkenness legitimately runs ahead of BAC on the rising limb (acute tolerance, fatigue, mixing). BAC measures blood alcohol, not how you feel. This is surfaced as honest copy, not faked into the number.

### Validated parameters (primary sources)

| Parameter | Literature | Current code | Change |
|---|---|---|---|
| Volume of distribution | Vd ≈ 0.7 L/kg (TBW) | Watson `r` ≈ 0.68 M | none |
| Elimination rate β (observed slope) | 0.0138–0.015 g/100mL/h | β 0.0138 M / 0.0157 F (age-adj) | retained as the *target* slope |
| Elimination Vmax (true max) | β is the slope at C≈0.08, not Vmax | n/a | **calibrate Vmax so M-M rate = β at C_ref=0.08 → Vmax ≈ 1.05·β** |
| Elimination kinetics | Michaelis–Menten | zero-order | **→ M-M** |
| Km (half-Vmax conc.) | human fits 0.02 g/L (Toxics 2023), pop-PK 0.038 g/L, Vestal in-vitro 0.06 g/L | n/a | **new const 0.004 g/100mL (0.04 g/L)** |
| FPM (fed) | ~20% of dose | 20% / 10% / 0% | none |
| Absorption `kA` (empty) | combined gut constant, gastric-emptying-limited; Tmax 36 min spirits / 54 wine / 60 beer (Mitchell 2014) | flat 6/h empty | **→ kA = f(%ABV), calibrated to Mitchell** |
| Peak Cmax ordering (same dose) | spirits 77 > wine 62 > beer 50 mg% | beverage-independent | reproduced by `kA(ABV)` |
| Population CV | ~20% | `bacCV = 0.20` | reused for verdict band |

Sources: Toxics 2023 (PMC10534806), Jones BCP (PMC2014954), Mitchell 2014 (PMC4112772), plus the existing research doc.

---

## 2. Scope

**In scope**
1. Michaelis–Menten elimination via forward numeric integration of the BAC curve (replaces closed-form `β·t`).
2. **Concentration-calibrated absorption `kA = f(%ABV)`** so the rising limb and peak (Tmax/Cmax) match Mitchell 2014 (§3.1a).
3. Full per-category serving-size presets feeding the existing dose calculation.
4. Safety-verdict reframe (no affirmative drive-OK; sub-legal impairment band; conservative verdict BAC).
5. Honest in-app note that felt intoxication can exceed BAC.
6. Tests validating the new model against published Cmax/Tmax and against zero-order for regression.

**Out of scope (explicitly not doing)**
- Two-compartment / full PBPK model (marginal gain, needs measured-BrAC feedback; irreducible 2–3× oral variance per Plawecki).
- Changing `r`/Watson, β values, FPM values — all validated as correct.
- Any water→BAC adjustment.
- Bayesian self-calibration from breathalyzer input (future work).

**Preserved invariants**
- Gulp detection → instant full Widmark absorption at the timestamp (deliberate UX; see research §9 and memory). Must survive the integration refactor.
- Public `BACCalculator` API signatures stable for existing callers where practical.

---

## 3. Component Design

### 3.1 Core model: forward integration (`BACCalculator`)

**What it does:** Produces the BAC-vs-time curve by integrating one ODE forward in time instead of evaluating a closed form per checkpoint.

**Why:** Michaelis–Menten elimination has no closed form for multi-dose accumulation; and per-instant evaluation of an integral is O(n²). One forward pass is O(n), exact, and naturally handles M-M, the gulp spike, and "eliminate only what's actually in blood."

**Algorithm.** Fixed integration step `dt = 1 min` (1/60 h). Let `C` = current BAC (g/100mL), starting at 0 at the first drink's timestamp.

For each step from first drink to the end time:
1. **Absorption input.** For every drink `i`, compute the *increment* in absorbed fraction over `[t, t+dt]`:
   `Δabsorbed_i = absorbedFraction_i(t+dt) − absorbedFraction_i(t)` (gulped drinks deliver their full fraction in the single step containing their timestamp).
   Convert to BAC gained:
   `ΔC_in = Σ_i [ dose_i · (1 − fpm_i) · Δabsorbed_i ] / (W · 1000 · r) · 100`
2. **Elimination output (Michaelis–Menten):**
   `ΔC_out = Vmax · C / (Km + C) · dt`, with `Km = michaelisKm = 0.004` and **Vmax back-calibrated from the validated β** (see below).
3. **Step:** `C = max(0, C + ΔC_in − ΔC_out)`.
4. Record `C` at output cadence (every 5 min, matching today's charts).

**New constants & Vmax calibration.** The published β values are the *observed descending-limb slope* (measured near C≈0.05–0.10), **not** the M-M Vmax. Setting `Vmax = β` would make elimination ~5% too slow at every concentration. Instead, pick Vmax so the M-M rate reproduces β at a representative mid-session BAC `C_ref = 0.08`:

```
michaelisKm  = 0.004            // g/100mL (0.04 g/L); human-fit midpoint
betaRefBAC   = 0.08             // g/100mL; concentration at which β was empirically measured
Vmax(profile) = eliminationRate(profile) * (michaelisKm + betaRefBAC) / betaRefBAC
              ≈ 1.05 * eliminationRate(profile)
```

This makes the model match the forensic β exactly at 0.08, run negligibly faster above it, and slow only below ~0.02 — the evidence-based tail correction. **Km sensitivity:** at C=0.02 the rate is ~0.87·β (Km=0.004) vs ~0.77·β (Km=0.006); both only affect the sober-time tail, never the peak. 0.004 is the empirically-grounded choice; documented so it can be tuned.

**Why one compartment.** The most accurate published models are multi-compartment M-M (Toxics 2023 3-comp AIC −1608 vs Widmark −215), but they require intercompartmental parameters (kCP, VC, VP, Q) that need blood sampling unavailable to a consumer app. Wilkinson showed one-compartment M-M is the identifiable limit for clean data. One-compartment M-M + first-order absorption + TBW Vd is therefore the correct, identifiable model for this use case; the only behavior it omits — the early arterial overshoot after rapid drinking — the gulp logic already over-represents in the conservative direction.

**Refactored shape:**
- New private core: `integrateBAC(entries:drinkTypes:weightKg:r:beta:sex:stomachState:stomachStateTimestamp:foodEntries:until:) -> [BACDataPoint]` — single forward pass; `until` optional (nil = run to ~zero).
- `bacAt(time)` → integrate `until: time`, return last point. Keeps signature for callers.
- `bacTimeline` → the integrated points directly (no more per-checkpoint loop calling `bacAt`).
- `estimatePeakBAC` → `max` over the integrated curve (scan to last drink + 2 h).
- `meanBACForEvent` → average of integrated points within the window.
- `currentBAC`, `projectedBAC` → `bacAt(Date())` / with the hypothetical drink appended.

**Inputs/deps:** `DrinkEntry`, `DrinkType`, `UserProfile`, `FoodEntry`, `StomachState`. **No new external deps.**
**Performance:** worst case ~12 h × 60 = 720 steps per single-instant call; charts one pass. Trivial on-device.

### 3.2 Elimination/zero-order vs M-M behavior (acceptance)

- At BAC ≈ 0.08: M-M rate = β **exactly** (by Vmax calibration). Peak essentially unchanged. **M-M does not raise the peak** — by design.
- At BAC > 0.08: rate is marginally faster than β (e.g. 1.02·β at 0.15) — negligible.
- At BAC ≤ 0.02: elimination visibly slows (0.87·β at 0.02, 0.75·β at 0.01); **time-to-zero is longer** than the old linear estimate. This is the corrected descending limb.
- Regression guard: the integrated curve in the 0.05–0.10 band must match the old closed-form within ±5% (test).

### 3.2a Absorption calibration: peak timing & height (`kA = f(%ABV)`)

**What it does:** Sets each drink's gut-absorption constant `kA` from its alcohol concentration so the integrated curve reproduces the empirically measured time-to-peak and peak-height ordering, instead of a single flat `kA` per stomach state.

**Why:** Gastric emptying — not intestinal uptake — is rate-limiting, and it depends on beverage concentration. Mitchell 2014 (0.5 g/kg, 20-min drink, fasted) measured, for the *same grams*:

| Beverage | %v/v | Tmax | Cmax |
|---|---|---|---|
| Spirits/mixer | 20% | **36 min** | 77 mg% |
| Wine | 12.5% | **54 min** | 62 mg% |
| Beer | 5% | **60 min** | 50 mg% |

Because elimination runs concurrently with absorption, slower `kA` → **lower and later peak** (beer), faster `kA` → **higher and earlier peak** (spirits). A flat fast `kA` (current 6/h) peaks ~30 min and treats beer like spirits — wrong on both axes.

**Model.** Absorption is fastest near ~20% v/v and slower for very dilute (beer) and very concentrated (neat spirits, pyloric slowing). Define a concentration-response on the *empty-stomach* `kA`:

```
kA_empty(abv) ≈ peak ~3.0/h near 15–25% v/v,
               falling to ~1.5/h at 5% (beer) and ~2.0/h at 40% (neat),
               then modulated DOWN by stomach state (food slows further).
```

Implementation: a small calibration function (lookup or smooth curve) whose constants are **fit so the integrated model lands within tolerance of the Mitchell Tmax/Cmax table** (asserted by tests, §6). Stomach state still scales `kA` down further (food delays/lowers peak — same direction as today). The drinking-duration `T` (user's stipulated average time × quantity) continues to spread the input as a zero-order infusion — validated best practice; this section only fixes the gut constant the infusion empties through.

**Interaction with gulp:** the gulp branch (instant absorption on rapid logging) is unchanged — a deliberate UX override of this curve for the rapid-pace case (research §9 / memory). Normally-paced isolated drinks now get correct Tmax.

**Direction-of-effect (honest):** spirits/shots read marginally higher and peak sooner; beer/wine read marginally lower and peak later. Net: the *curve across time* is correct; this is not a uniform increase. It also makes `estimatePeakBAC` and the "still rising / peaks at ~X" projection (used by the verdict) accurate.

### 3.3 Dose fidelity: serving-size presets

**What it does:** Lets the user record the *actual* pour, not a fixed standard serving.

**Model additions**
- `struct ServingSizeOption { let id: String; let label: String; let volumeMl: Double }`.
- `DrinkType.servingSizeOptions: [ServingSizeOption]` — computed from `drinkCategory` and `defaultVolumeMl`:
  - **spirits / agave** (44 mL base): Single 44 · Double 88 · Triple 132.
  - **wine** (150 mL base): Small 125 · Standard 150 · Large 250.
  - **beer / seltzer** (355 mL base): Bottle/Can 355 · Pint 568 · Half 500.
  - **cocktails** (240 mL base): Single 240 · Strong/Double 360 (extra spirit; volume proxy for strength).
  - Fallback: Standard = `defaultVolumeMl`, plus a ×2 option.
- `DrinkEntry` gains optional `servingSizeLabel: String?` (display only). The chosen pour is stored in the **existing** `volumeOverrideMl`, so the dose math is untouched — `calculateAlcohol` already reads `volumeOverrideMl`.

**UI**
- Quick-add (`QuickAddGrid` in `ActiveEventView`) and `EditEntryView` / `EditDrinkView`: a compact size selector (segmented or menu) defaulting to **Standard**. Selecting a non-standard size sets `volumeOverrideMl` + `servingSizeLabel`.
- Timeline chips / breakdown show the label when not Standard (e.g., "Whiskey · Double").

**Why presets over a raw mL field:** one tap captures the common real-world cases (the home double, the big wine pour) that drive under-counting, without forcing the user to measure.

### 3.4 Safety verdict reframe (`WarningSystem` + `ActiveEventView`)

**Verdict BAC** (conservative): `verdictBAC = max(currentBAC × (1 + bacCV), projectedPeakBAC)`
— upper edge of the ±20% band, and if BAC is still rising, the projected peak. Never optimistic.

**Impairment thresholds** (independent of, and combined with, the legal limit):
- `verdictBAC ≥ legalLimit` → **danger** "Over your legal limit."
- `verdictBAC ≥ 0.05` (even if legal limit is higher, e.g. 0.08) → **danger** "Impaired — do not drive."
- `0.02 ≤ verdictBAC < 0.05` → **warn** "Impairment has begun."
- `verdictBAC < 0.02` → **neutral/info**, copy: *"Effects may still be present. This app can't confirm it's safe to drive."* — **never an affirmative green "OK to drive."**

**UI changes (`ActiveEventView`)**
- `overLimit` trigger for `DriveWarningBanner` changes from `currentBAC >= bacLimit` to `verdictBAC >= min(0.05, bacLimit)` (driving mode).
- "until safe to drive" countdown integrates the **M-M tail** and counts down to the impairment floor (`min(0.05, legalLimit)` → then to 0.02 messaging), not just the legal number — so it reads longer and honest.
- Remove/replace any affirmative drive-OK affordance; the sub-limit state shows the neutral non-affirmation copy.
- Per-drink `safeDriveLabel` ("Safe ~time"): relabel to "Legal ~time" / drop the word "safe," and base it on `verdictBAC` + M-M.

**`WarningContext`** gains `verdictBAC` (and keeps `currentBAC`); `buildWarnings` uses `verdictBAC` for the driving branch and the new tiered copy.

### 3.5 Honest subjective-gap note

A short, dismissible info element (BAC hero footnote or `LearnView` section): *"You may feel more impaired than your BAC suggests — especially while it's rising. BAC estimates blood alcohol; it can't measure how you feel. When in doubt, don't drive."* No numeric effect.

---

## 4. Data Flow

```
DrinkEntry(volumeOverrideMl ← serving size, abvOverride, quantity)
        │
        ▼
calculateAlcohol → dose grams (unchanged)
        │
        ▼
integrateBAC(forward, dt=1min):  ΔC_in (absorption, FPM) − ΔC_out (M-M)  → C(t) curve
        │                                   │
        ├── currentBAC / bacAt(now) ────────┤
        ├── estimatePeakBAC = max(curve)    │
        ├── bacTimeline = curve             │
        └── meanBACForEvent = avg(window)   │
        │
        ▼
verdictBAC = max(current×1.2, projectedPeak)
        │
        ▼
WarningSystem.buildWarnings → tiered impairment / drive messaging (never affirmative)
        │
        ▼
ActiveEventView: DriveWarningBanner / BACHero / countdown
```

---

## 5. Error Handling & Edge Cases

- `weightKg <= 0` or `r <= 0` → return 0 / empty (as today).
- No entries → empty curve.
- Integration step containing a gulped drink adds the full Widmark mass in that single step → preserves the instant spike; `max(0, …)` keeps `C` non-negative.
- Drinks logged out of order → entries sorted by timestamp before integration (as today).
- BAC returning to 0 mid-session then a later drink: forward integration handles naturally (no `max(0, sum − β·t)` artifact).
- Legal limit higher than 0.05 (e.g., 0.08 US): the 0.05 impairment-danger tier still fires below the legal line — the safety improvement.
- Existing persisted `DrinkEntry`/`NightEvent` without the new optional field decode fine (optional, defaulted).

---

## 6. Testing Strategy

Extend `siptrackTests/BACCalculatorCoreTests.swift` and `BACCalculatorFoodTests.swift`:

1. **M-M tail:** time-to-zero with M-M > zero-order for the same dose; curve stays positive below 0.02 longer.
2. **High-BAC regression:** at C ≥ 0.08 the integrated curve matches the old closed-form within ±5%.
3. **Published-peak fixtures (Mitchell 2014, 0.5 g/kg, empty, 80 kg male):** Cmax spirits ≈ 0.077, wine ≈ 0.062, beer ≈ 0.050; **Tmax spirits ≈ 36, wine ≈ 54, beer ≈ 60 min**. Assert each peak within the ±20% band, Tmax within ±15 min, and the strict ordering spirits > wine > beer for Cmax and (earliest) spirits < wine < beer for Tmax. **This is the calibration target for `kA = f(%ABV)`.**
4. **Gulp preserved:** two drinks 1 min apart → first drink's full mass present at its timestamp (existing test must still pass).
5. **Dose fidelity:** Double pour → exactly 2× grams → BAC scales linearly.
6. **Verdict:** never returns affirmative "safe to drive"; uses upper band; rising-limb → verdict ≥ current; 0.05 danger tier fires even when legalLimit = 0.08.
7. **Water:** `applyHydration` still returns input unchanged (guard against regressions).

Validation target (per research doc §7): mean prediction within ~15–20% of measured, conservative direction near the limit.

---

## 7. Rollout / Migration

- New `DrinkEntry.servingSizeLabel` is optional & Codable-compatible — no migration.
- `michaelisKm`, `integrateBAC`, `verdictBAC` are additive; closed-form `estimateBAC` legacy API retained for any non-timeline caller.
- Update the model header comment + `.planning/research/BAC-ACCURACY-RESEARCH.md` §2/§3/§9 to reflect M-M elimination and the verdict change.
- `LearnView` in-app copy updated for M-M + the subjective-gap note.

---

## 8. Sources

- Mackowiak et al. "Pharmacokinetic Analysis of Ethanol: New Modification of Mathematic Model." Toxics 2023. PMC10534806. (Vd 0.7 L/kg; FPM ~20%; M-M elimination; β 0.0014–0.0028 g/L/min.)
- Jones et al. "Within- and between-subject variations in PK parameters of ethanol." Br J Clin Pharmacol. PMC2014954. (M-M Vmax/Km; one- vs two-compartment; Km ~0.06 g/L.)
- Mitchell et al. "Absorption and Peak BAC After Beer, Wine, or Spirits." ACER 2014. PMC4112772. (Cmax/Tmax fixtures; concentration → gastric-emptying/peak; same dose → spirits 77/36min, wine 62/54min, beer 50/60min.)
- Plawecki/Ramchandani PBPK & CAIS (PMC3370150; ACER 1999 BrAC clamp). (Oral dosing has 2–3× inter-person range in ascending slope/peak latency → ceiling on drink-log-only prediction; justifies one-compartment.)
- Toxics 2023 Appendix A.1: gastric emptying is rate-limiting; one gut compartment with a combined `kA`; zero-order input over drinking duration is the practical absorption model.
- Existing: `.planning/research/BAC-ACCURACY-RESEARCH.md` (full bibliography, §9 gulp rationale).
- NIH/NIAAA standard-drink vs real-pour overpour (30–50%).
- Acute tolerance / subjective-vs-measured: PMC7686294; Duke APEP.
```
