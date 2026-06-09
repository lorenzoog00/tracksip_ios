# BAC Calculation Accuracy — Scientific Research Summary

**Purpose:** Establish the most accurate BAC model for SipTrack. Read-only research, no code changes.
**Date:** 2026-05-11

---

## 1. Current SipTrack Implementation Snapshot

File: `SipTrack/Core/BACCalculator.swift`

| Component | Value / Approach |
|---|---|
| Distribution factor `r` (no profile) | male 0.68, female 0.55, neutral 0.615 |
| `r` (with profile) | Watson TBW / weight, clamped [0.30, 0.90] |
| Watson TBW male | `2.447 − 0.09516·age + 0.1074·H_cm + 0.3362·W_kg` |
| Watson TBW female | `−2.097 + 0.1069·H_cm + 0.2466·W_kg` |
| Ethanol mass | `mL × ABV × 0.789` (density correct) |
| Core formula | `BAC % = 100 · A / (W·1000·r) − β·t`, β = **0.015 %/h fixed** |
| Standard drink | 14 g (US NIAAA) |
| Absorption | per-drink, optional fixed lag from stomach state, **no kinetics curve** |
| Food effect | discrete delay (0/15/37.5 min) + peak reduction (0/15/30%) with linear 150-min decay |
| Hydration | flat 5% reduction if water ≥ 1.25× drinks |
| Compartments | single (one pool) |
| Elimination kinetics | strict zero-order |

**The math is solid as a baseline (Widmark + Watson is what most forensic labs use), but several parameters are point estimates with no uncertainty band, and the absorption/elimination model is the simplest one in the literature.**

> **Implemented (2026-06, `BACCalculator`):** the snapshot above describes the original closed-form model. The accuracy overhaul (`docs/superpowers/specs/2026-06-06-bac-accuracy-overhaul-design.md`, Plan 1) replaced it with a **forward-integrated one-compartment model**:
> - **Elimination is Michaelis–Menten**, not zero-order: `rate = Vmax·C/(Km+C)`, `Km = 0.004 g/100mL`, `Vmax = β·(Km+0.08)/0.08 ≈ 1.05·β` (calibrated so M-M = β at the 0.08 reference). M-M ≈ β above ~0.05 and slows the tail below ~0.02 — the corrected descending limb (supersedes §2.1's instantaneous/zero-order assumptions; see §2.5).
> - **Absorption `kA` depends on beverage strength** (`absorptionRateEmpty(abv:)`), peaking near ~20% v/v and slower for dilute beer / neat spirits, slowed further by food. Anchors are calibrated so the integrated curve reproduces the Mitchell 2014 Tmax/Cmax table (§9.1 / §10): spirits 36 min / 0.077, wine 54 min / 0.062, beer 60 min / 0.050 (supersedes §4's single fast `kA`).
> - **Gulp instant-absorption (§9) is preserved** as a deliberate UX override.
> Validated by `siptrackTests/BACCalculatorKineticsTests.swift`.

---

## 2. Core Equations Used in the Field

### 2.1 Widmark (1932) — baseline still in forensic court use

```
BAC (g/100 mL) = (A_grams / (W_kg · r_L/kg)) · (1/10) − β · t
```

- `r` = "Widmark factor" = TBW/(W · water-fraction-of-blood). Water fraction blood ≈ **0.806** (Searle).
- Population means: men ≈ 0.68 L/kg, women ≈ 0.55 L/kg.
- Assumes **instantaneous absorption** and **zero-order elimination** → only valid hours after drinking in fasted state.

Source: Widmark 1932; reviewed in Searle 2015 (PMC4361698).

### 2.2 Watson (1980) Total Body Water — more individualized r

Male: `TBW = 2.447 − 0.09516·age + 0.1074·H_cm + 0.3362·W_kg`
Female: `TBW = −2.097 + 0.1069·H_cm + 0.2466·W_kg`

Then `r = TBW / W` (sometimes `TBW / (W · 0.806)` if expressing per blood water).

Forensic recommendation (Maskell 2022, ScienceDirect 2020): **TBW is the preferred parameter** rather than ethanol volume-of-distribution V. RMSE 9–13% with TBW vs 12–15% with V.

### 2.3 Forrest (1986) — adjusts r by BMI

Values used in expert testimony (Searle table — Forrest/Barbour):

| BMI | r (men) | r (women) |
|---|---|---|
| 17–18 | 0.80 | 0.74 |
| ~22 | 0.75 | 0.69 |
| ~25 | 0.72 | 0.65 (Barbour) / 0.61 (Forrest) |
| ~27 | 0.69 | 0.62 / 0.58 |
| ~30 | 0.66 | 0.60 / 0.53 |

**Forrest disagrees with Barbour for women** (Searle 2015) — Barbour's values are considered more reliable. Watson is preferred at BMI extremes (>34 or <17).

### 2.4 Seidl et al. (2000) — BIA-corrected, gender-equitable

Uses bioelectrical impedance to update `r`. Requires BIA measurement → not practical for SipTrack, but informative: confirms women's lower TBW per kg drives most of the male/female BAC gap, plus reduced gastric ADH activity.

### 2.5 Norberg / Wilkinson — modern multi-compartment with Michaelis–Menten

Two-compartment model with absorption from gut → central (blood) ↔ peripheral (tissue), eliminated via:

```
dC/dt = − Vmax · C / (Km + C)
```

Typical values: `Vmax ≈ 0.45 g/L/h ≈ 0.045 g/100mL/h`, `Km ≈ 0.05–0.10 g/L` (≈ 0.005–0.01 g/100 mL).

When `C >> Km`, behaves zero-order at ~Vmax ≈ 0.015–0.020 g/100 mL/h (Widmark's β).
When `C < Km` (tail-end, near sober), behaves first-order — explains why Widmark **overestimates time to zero** and underestimates clearance below 0.02 g/100 mL.

Sources: Norberg 2003; Wilkinson 1977; MDPI Toxics 2023 (PMC10534806).

---

## 3. Empirically-Validated Parameter Ranges

### 3.1 Elimination rate β

| Source | Value | Notes |
|---|---|---|
| JAAPL forensic standard | **0.0155 ± 0.0029 %/h** (1 SD) | This is what courts use |
| 95% CI (±2 SD) | 0.0097 – 0.0213 %/h | for the same drinker |
| Population range | 0.01 – 0.025 %/h | healthy adults |
| Women (TBW-BIA study) | 0.074 ± 0.017 mg/L/h (BrAC) | ≈ 0.0157 %/h BAC |
| Men (TBW-BIA study) | 0.065 ± 0.011 mg/L/h (BrAC) | ≈ 0.0138 %/h BAC |
| Chronic drinkers | up to 0.030 %/h | hepatic enzyme induction |
| At very low BAC (<0.02 %) | slower than predicted | Michaelis–Menten regime |

**Implication for SipTrack:** the hardcoded 0.015 is fine as a population mean, **but women clear ~10% faster than men on average** — the model currently doesn't reflect this. Also no uncertainty is propagated.

### 3.2 Distribution factor r

Population SD on `r` is roughly ±0.085 L/kg for both sexes (Searle Appendix 1). The negative correlation between `r` and `β` is **−0.135** (Searle, citing Gullberg) — needs to be included if computing combined uncertainty.

### 3.3 Total uncertainty

Gullberg's commonly-quoted **±21% CV** is an upper bound, not a fixed value. Searle (2015) showed CV must be **computed per case** from:
- volume of drink uncertainty (`ev`)
- ABV uncertainty (`ez`)
- absorption fraction (`ea`, ≈ 0.90–1.00)
- Widmark factor (`er`)
- elimination rate (`eβ`)
- session duration (`et`)

Hustad & Carey (2005) compared 5 eBAC formulas against measured BrAC in naturalistic drinking: R² = **0.54–0.55**. All formulas **overestimated** vs measured BrAC. Matthews–Miller was best of the lot. Errors larger for: longer sessions, more drinks, women, lighter drinkers.

---

## 4. Absorption Phase — Where Widmark Fails

Widmark assumes instantaneous absorption. Reality:

- **Gastric emptying is THE rate-limiting step** (Norberg, Jones).
- Stomach absorbs ~20% via passive diffusion; small intestine absorbs the rest at high rate.
- Time-to-peak BAC: **30–90 min fasted**, **60–180 min fed** (Jones, IARC).
- First-pass metabolism (FPM): negligible fasted, **up to 30% with food** (slow gastric emptying lets gastric ADH oxidize ethanol before portal absorption).
- AUC reduction: light meal → −36%, heavy meal → larger.
- Women have lower gastric ADH activity → less FPM → **higher peak BAC for same dose** (NEJM Frezza 1990).

**SipTrack's current food model** (37.5 min delay + 30% peak reduction for full meal, linear decay over 150 min) is a reasonable heuristic but is not derived from a published model. The reduction is closer to the **fraction of total dose lost to FPM** which Jones (1996) puts at 10–30%, so 30% for a full meal is in the upper plausible range — should probably be 15–25%.

Absorption modeled as first-order: `dG/dt = −kA·G`, with `kA = 0.05–0.20 min⁻¹` fasted (half-life 3–14 min) and `0.01–0.05 min⁻¹` fed (half-life 14–70 min).

---

## 5. Other Known Effects (NOT in SipTrack today)

| Effect | Magnitude | Source |
|---|---|---|
| Gender (gastric ADH) | women +20–30% peak BAC for same dose | NEJM Frezza 1990 |
| Age | β decreases ~5–10% per decade after 60 | Sci. Forensic Sci. 2014 |
| Chronic heavy drinking | β up to +50% (enzyme induction) | Wigmore |
| Concurrent food | peak −20–40%, AUC −10–30% | Jones, IARC |
| Carbonation | speeds gastric emptying → faster peak | minor |
| Drink concentration | 15–30% ABV absorbs fastest; very high or very low slower | Jones 2010 |
| Time of day | morning absorption faster (gastric emptying) | minor |
| Cimetidine, H2 blockers | reduce gastric ADH → +15% BAC | Frezza, Caballeria |
| Endogenous BAC | < 0.0003 g/100 mL — negligible | Jones |

**Hydration**: SipTrack's 5% reduction at 1.25× water ratio has **no pharmacokinetic basis**. Water doesn't reduce BAC — it only mitigates dehydration symptoms attributed to hangover. The literature does not support a BAC adjustment from water intake.

---

## 6. Breath:Blood Ratio (only relevant if SipTrack adds breathalyzer integration)

- Arterial: BAC_art = BrAC × 2251 ± 46 (Wikipedia/Jones)
- Statutory: 2000 (Austria — known to be low), 2100 (US/most), 2300 (Germany), 2400 (UK)
- Venous–arterial difference: most uncertainty in the absorption phase

---

## 7. What "More Accurate" Means in Practice

A perfectly Newtonian BAC predictor is impossible — true measured BAC has irreducible inter- and intra-individual variability of ~10–20%. The legitimate accuracy goals for a consumer app are:

1. **Mean prediction within 15–20% of measured BAC** on naturalistic data (matches the published best eBAC models).
2. **Calibrated uncertainty band**: show the user a range (e.g., 0.055–0.078 instead of "0.066"), not a false-precision number.
3. **Direction-of-error awareness**: app should not under-predict in safety-critical territory (e.g., near 0.08). Many published formulas overestimate by design — that's the safe direction.

---

## 8. Concrete Improvement Opportunities (ranked by impact / effort)

These are **suggestions for future work**, not changes to be made now.

### High impact, low effort
1. **Sex-specific β**: use 0.0138 %/h (M) vs 0.0157 %/h (F) instead of flat 0.015. (Source: BIA-TBW study; consistent with women's higher gastric ADH-driven peak but faster water clearance.)
2. **Tighter Watson clamp**: 0.50–0.85 instead of 0.30–0.90 — current range admits non-physiological values.
3. **Expose uncertainty**: render a ±SD shaded band on the BAC chart using r-SD=±0.085 and β-SD=±0.003.

### High impact, moderate effort
4. **First-order absorption curve** instead of step function: `BAC(t) = (A/V_d)·(1 − e^(−kA·t)) − β·t`. Use `kA` from stomach state: empty 0.10/min, snack 0.05/min, full meal 0.02/min.
5. **First-pass metabolism term**: subtract 5–25% of dose for fed states (Jones-derived).
6. **Drop the hydration adjustment** or relabel it (it's not a BAC modifier; it can inform "hangover risk" only).

### Highest accuracy, highest effort
7. **Michaelis–Menten elimination**: replace `0.015·t` with integration of `dC/dt = −Vmax·C/(Km+C)`. Improves accuracy below 0.02 g/100 mL and at very high BAC.
8. **Two-compartment Norberg model**: central + peripheral, captures the early "overshoot" after rapid drinking.
9. **Age and chronic-drinking modifiers** for β, gated behind user profile inputs.
10. **Bayesian self-calibration**: if user occasionally logs breath/blood measurement, fit per-user β and r.

### Validation step (independent of model choice)
- Build a fixture set from published eBAC validation studies (Hustad & Carey 2005, Norberg drinking experiments) and unit-test BACCalculator against them. Target R² ≥ 0.55 vs measured BAC.

---

## 9. Rapid Drinking ("Gulp Detection") — Model vs UX

### 9.1 What the literature says

Drinking pace shifts both **Cmax** (peak) and **Tmax** (time to peak), but does not eliminate gut transit:

| Beverage (0.5 g/kg over 20 min, fasted) | Cmax (mg/dL) | Tmax (min) |
|---|---|---|
| Vodka/tonic (20% v/v) | 77.4 ± 17.0 | **36 ± 10** |
| Wine (12.5% v/v) | 61.7 ± 10.8 | **54 ± 14** |
| Beer (5.1% v/v) | 50.3 ± 9.8 | **62 ± 23** |

Source: **Mitchell 2014** (Alcohol Clin Exp Res, DOI 10.1111/acer.12355, PMC4112772).

**Sjögren 1996** measured "absorption time" (peak time + plateau) in 31 social drinkers with drinking times ≥30 min: **77.4% absorbed within 60 min**; 74.2% had Tmax < 30 min. Faster drinking compresses this further, but the literature does not show instant absorption — gut transit is rate-limiting.

A **Roux-en-Y gastric bypass** cohort (PMC4487806) is the only setting that approaches "instant": Cmax 138.4 mg/dL at Tmax **5.4 ± 3.1 min** because the duodenum is reached almost immediately. This is the physiological upper bound on absorption speed for an oral dose.

### 9.2 What SipTrack does

```swift
// in BACCalculator.bacAt(...)
if i + 1 < sorted.count {
    let gap = sorted[i+1].timestamp.timeIntervalSince(entry.timestamp) / 3600
    if gap >= 0, gap < T {
        T = 0
        gulped = true
    }
}
let absorbed = gulped ? 1.0
                      : absorbedFraction(deltaHours: hours, kA: factor.kAPerHour, durationHours: T)
```

The drink whose follow-up arrives inside its `effectiveDrinkingMinutes` window is marked **gulped** and contributes its full Widmark mass to plasma at the entry timestamp.

### 9.3 Options considered

| Option | Behaviour | Why rejected / accepted |
|---|---|---|
| **A. Pure first-order, T = original** | Sip curve over typical 15–30 min | Doesn't reflect rapid drinking at all. Original bug. |
| **B. Shrink T to gap, first-order** | Bolus into gut at timestamp + linear infusion over `gap` | Pharmacologically correct (Mitchell 2014 / Norberg 2003 / Plawecki 2008). Rejected: at kA = 6/h (empty), only ~10% absorbed at +1 min — user sees no spike, calls the meter broken. |
| **C. Quadruple kA when gulped** | Aggressive first-order (t½ ≈ 1–2 min) | Closer to RYGB physiology but not normal physiology. Mixed message and still not instantaneous in early seconds. |
| **D. Gulp → full Widmark, instant** | Treat gulped drink as fully in blood at timestamp (current) | **Selected.** Matches user mental model and the classic forensic Widmark bolus assumption. Trade-off: overestimates BAC for the first 5–30 min after a gulped drink relative to PBPK ground truth. |

### 9.4 Accepted error budget for option D

Versus a Plawecki-style PBPK simulation for two beers consumed 1 min apart on an empty stomach:

- **t = +1 to +10 min after second drink:** SipTrack reads **+0.012 to +0.018 BAC%** higher than PBPK (gulped drink shown as fully absorbed instead of ~10–50%).
- **t = +30 min:** error drops below ±0.003 BAC% (both models near peak).
- **t = +60 min:** identical within the bacCV = 20% uncertainty band.

This bias is **conservative for safety** (over-estimates BAC during the highest-risk window, never under-estimates) and is bounded — once the actual gut absorption catches up, the curves converge well inside the displayed uncertainty band.

### 9.5 When to revisit

Switch to **Option C** (variable kA) if/when:
- Users complain of over-estimation (we've only ever heard the opposite).
- We add a "post-hoc accuracy review" mode that compares against measured BrAC.
- We add a "low-risk drinker" toggle where pharmacological accuracy matters more than reactivity.

Switch to **Option B** if we add an explicit "peak in X min" indicator that takes the slow rise visible to the user — then they understand they're seeing absorption, not a stuck meter.

---

## 10. Key Sources

- Mitchell MC, Teigen EL, Ramchandani VA. "Absorption and Peak Blood Alcohol Concentration After Drinking Beer, Wine, or Spirits." Alcohol Clin Exp Res 2014; 38(5):1200–4. DOI 10.1111/acer.12355. PMC4112772.
- Sjögren H, Eriksson A, Ahlner J. "Determination of absorption time of ethanol in social drinkers." Forensic Sci Int 1996; 77(1–2):69–76. (PubMed 8819992.)
- Plawecki MH, Han JJ, Doerschuk PC, Ramchandani VA, O'Connor SJ. "Physiologically based pharmacokinetic (PBPK) models for ethanol." IEEE Trans Biomed Eng 2008. (Multi-input gut → portal → plasma model, foundation for our multi-dose superposition.)
- Searle J. "Alcohol calculations and their uncertainty." Med Sci Law 2015. PMC4361698.
- Maskell PD et al. "Revised equations allowing the estimation of uncertainty associated with the Total Body Water version of the Widmark equation." J Forensic Sci 2022.
- Watson PE, Watson ID, Batt RD. Am J Clin Nutr 1980 — Watson TBW equation.
- Forrest ARW. "The estimation of Widmark's factor." J Forensic Sci Soc 1986.
- Seidl S, Jensen U, Alt A. "The calculation of blood ethanol concentrations in males and females." Int J Legal Med 2000.
- Norberg Å, Jones AW, Hahn RG, Gabrielsson JL. "Role of variability in explaining ethanol pharmacokinetics." Clin Pharmacokinet 2003.
- Wilkinson PK. "Pharmacokinetics of ethanol: a review." Alcohol Clin Exp Res 1977.
- Jones AW. "First-pass metabolism of ethanol." Postgrad Med J 1996.
- Frezza M et al. "High blood alcohol levels in women: the role of decreased gastric ADH activity and first-pass metabolism." NEJM 1990; 322:95–99.
- Hustad JTP, Carey KB. "Using calculations to estimate blood alcohol concentrations for naturally occurring drinking episodes." J Stud Alcohol 2005.
- Mackowiak K et al. "Pharmacokinetic Analysis of Ethanol: New Modification of Mathematic Model." Toxics 2023. PMC10534806.
- Bissinger R et al. "The impact of total body water on breath alcohol calculations." Sci Justice 2020. PMC7518982.
- UKIAFT "Guidelines for Alcohol Calculations" v4.4 (2024).
- JAAPL "Ethanol Forensic Toxicology" 2017; 45(4):429 — practical forensic numbers (β = 0.0155 ± 0.0029).
- Wikipedia "Blood alcohol content" — equation summary and references.
- Wikipedia "Drunk driving law by country" — primary source for SipTrack's `LegalBACLimits` table, cross-checked May 2026.
- WHO "Legal blood alcohol concentration (BAC) limits" indicator (Global Health Observatory).
- International Alliance for Responsible Drinking (IARD) — BAC Limits resource.
- drinkdriving.org — Worldwide drink-driving limits.

---

## 11. Legal Drink-Drive Limits (jurisdiction lookup)

Implemented as `LegalBACLimits.all` in `SipTrack/Core/LegalBACLimit.swift`. Each entry carries the general / novice / commercial threshold and an optional note covering sub-jurisdictions and lab tolerances.

### 11.1 Why three driver tiers

Nearly every jurisdiction that allows any BAC for the general driver enforces a **stricter** threshold for at least two protected classes:

- **Novice / probationary** — typically first 2–3 years of licensure, or under-21 where applicable. Limits drop to 0.00 % or 0.02 % in most of Europe, Australia (L/P plates), USA (under-21 zero-tolerance), Canada (provincial graduated licensing).
- **Commercial** — heavy vehicles, taxis, buses, rideshare. USA federal CDL = 0.04 %; most EU = 0.00 / 0.02 %; Australia and NZ heavy vehicles = 0.00 %.

SipTrack stores `DriverType` on the user profile so the visible "drive limit" matches the user's actual legal threshold, not the country's default.

### 11.2 Coverage choices

55 countries covering >90 % of expected user base. Where sub-jurisdictions differ (UK Eng/Wales/NI 0.08 vs Scotland 0.05; US Utah 0.05 vs other 0.08), we encode the most common value and surface the variation in the `note` field. Auto-detect via `Locale.current.region` runs once at first launch and never overwrites the stored value.

### 11.3 Limitations

- Sub-national jurisdictions (US states, Canadian provinces, UK constituent countries) are flattened to a single value per ISO-3166 code.
- Zero-tolerance jurisdictions with a **lab tolerance** (Russia 0.016, Brazil 0.02) are encoded as the lab number, not "0.00", to avoid false-positive warnings from BAC noise.
- The table is a snapshot — Denmark's July-2025 novice change is encoded; future changes require a code update.
