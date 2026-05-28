# AI Reports Redesign

**Date:** 2026-05-25
**Status:** Approved

## Problem

The current AI reports restate stats the user already sees on screen. The weekly and monthly prompts send raw numbers to Claude and Claude echoes them back with medical framing. The daily recovery brief is generic. None of this feels new or useful to the user.

## Goal

Make each report feel like advice from a knowledgeable friend — not a doctor writing a clinical summary, not an app recapping your data. The AI should say things the user could not figure out themselves from staring at the screen.

**Core rule across all reports:** Never tell the user to drink less. Never moralize. Assume they are going out and help them do it smarter.

---

## Three-Tier Design

### Daily — Recovery Card

**One job:** Help you recover from exactly what you drank tonight.

**Content:**
- If it was a good night (low BAC, paced well, met goal) → praise it and name what worked
- If it was a heavy night → drink-type-specific recovery tips + one smarter alternative for next time
- Drink type drives everything: tequila, beer, wine, spirits, and mixed combos each get different advice
- No stats recap. No generic "drink water and rest."

**Voice:** Short, practical, tonight-actionable. Friend who knows what tequila does to you.

**Example — heavy tequila night:**
> "You went hard on tequila tonight. That one hits different — plan on feeling it tomorrow morning. Drink a big glass of water before you sleep and eat something greasy if you can. Skip the Tylenol, grab ibuprofen instead if you wake up rough. Next time, try switching to beer after the first couple of shots — same vibe, way easier morning after."

**Example — clean beer night:**
> "Solid night honestly. You kept it to beer, paced yourself, stayed under your goal. That's how you go out and actually feel fine tomorrow. Nothing to recover from — just sleep well. Keep doing it like this."

**Sections:** 1 paragraph, no labeled sections needed.

---

### Weekly — Story Card

**One job:** Tell the honest story of the week.

**Content (2 sections):**
1. **The Week** — what happened, name the outlier night if there was one. No stats recapping — narrative only.
2. **What You Nailed** — one specific thing they actually did well this week (code pre-computes this: best hydration night, earliest end time, cleanest BAC night, food before drinking). AI names it so they repeat it.

**Voice:** Casual, reflective. 3 sentences max per section. No forward-looking advice, no "next week try X."

**Example — The Week:**
> "Saturday was most of your week — the rest of it was actually pretty clean. You tend to lose track after midnight on weekends but your mid-week nights were some of your best in a month."

**Example — What You Nailed:**
> "You ate before drinking on 3 out of 4 nights this week. That's why your peaks stayed lower than they usually do — keep doing that."

---

### Monthly — Deep Analysis Card

**One job:** Full honest picture of the month with clinical depth.

**Content (4 sections — structure unchanged):**
1. **Medical Analysis** — clinical assessment of BAC peaks, organ load, back-to-back nights. References user physique. Honest.
2. **Nutrition & Metabolism** — impact of specific drinks consumed, caloric total, hydration pattern, one concrete tip.
3. **Behavioral Insight** — the signature move: the habit they repeat without knowing it. Code pre-computes this (e.g. always accelerates after midnight, always mixes on weekends, always front-loads). AI names it memorably. Also includes best night of the month and why it worked.
4. **Overall Synthesis** — two sentences tying all three together. Honest and motivating.

**Voice:** Clinical and direct. The monthly earns its formality. No moralizing but no softening either.

---

## Implementation Approach — C (Pre-compute + Narrate)

Code finds the facts. Claude writes the story. Claude never has to "figure out" patterns — it receives them as structured data and narrates them.

### What code pre-computes (iOS or Firebase function):

**For weekly:**
- Outlier night (highest drinks night)
- Best behavior this week (highest hydration night, earliest end time, lowest BAC night, food-before-drinking count)

**For monthly:**
- Best night of the month (lowest BAC or best-paced)
- Signature move (dominant pattern: front-loaded drinking, post-midnight acceleration, consistent mixing)
- Month vs previous month delta (better / worse / flat)

**For daily:**
- Drink type breakdown (dominant drink category: tequila/spirits, beer, wine, mixed)
- Whether the night was "good" or "heavy" (vs user's goal / BAC threshold)

These facts are injected into the prompts as structured context. Claude is instructed to narrate them, not discover them.

---

## UI Changes

**Applies to:** `CoachReportCard.swift`, `AIReportCard.swift`

| Element | Before | After |
|---|---|---|
| Section labels | Collapsible bars with colored left border | Colored pill labels, always open |
| Section body | Collapsed by default, tap to expand | Always visible |
| Header | Keep as-is | Keep as-is |
| Serif body text | Keep as-is | Keep as-is |
| EKG animation (loading) | Keep as-is | Keep as-is |
| Gold gradient rule | Keep as-is | Keep as-is |

**Pill label design:** Small rounded badge with section color background (12% opacity) and colored text. Same color coding as today (blue = medical, green = nutrition, purple = behavioral, gold = synthesis).

---

## Files Affected

| File | Change |
|---|---|
| `functions/index.js` | Rewrite all 4 prompt builders + add pre-computed insight injection |
| `SipTrack/Views/Coach/CoachReportCard.swift` | Replace `SectionRow` collapse behavior with open pill layout |
| `SipTrack/Views/Summary/AIReportCard.swift` | Apply pill label style, remove collapse |
| iOS data layer (TBD) | Pre-compute weekly/monthly insights before sending to Firebase |

---

## Mapping to Existing Code

| Report | Firebase function | iOS card |
|---|---|---|
| Daily | `generateNightReport` | `AIReportCard.swift` |
| Weekly | `generateCoachReport` (type: weekly) | `CoachReportCard.swift` |
| Monthly | `generateCoachReport` (type: monthly) | `CoachReportCard.swift` |

`generateRecoveryBrief` (morning-after card) is **not changed** in this spec.

---

## Out of Scope

- Comparison report (`buildComparisonPrompt`) — stays unchanged
- `generateRecoveryBrief` — morning-after card, separate scope
- Notification / push triggers
- Any feature that tells the user to reduce drinking frequency
