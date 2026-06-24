# SipTrack — From Instrument to Companion

**Date:** 2026-06-23
**Status:** Direction agreed with product owner
**Scope:** The 90 minutes the app is actually open — the live night.

---

## Framing

SipTrack today is an excellent **instrument**: a research-grade BAC engine
([BACCalculator.swift](../SipTrack/Core/BACCalculator.swift)), AI reports, Live
Activity, Watch app, country-aware legal limits, pace/calorie/stage warnings.

It is not yet a **companion**. A companion is proactive, near-zero friction in
the moment, and helps you get home safely. The work below closes that gap.

**Principle:** don't add new feature surfaces (Coach, Challenges, Compare,
Calendar already exist). Go deep on the live night.

---

## P0 — Near-zero-tap re-logging *(agreed: top priority)*

**Problem.** By drink 5 the user is impaired, one-handed, in a dark loud room.
Logging today is: open app → into event → scroll to picker → find tile → tap.
Too many taps at exactly the moment dexterity and patience are lowest.

**Goal.** Logging "another one" should cost the fewest taps physically possible.

**Direction.**
- A dominant **"Same again"** action that repeats the last drink in one tap.
  The data is already known — [DrinkToast](../SipTrack/Views/Event/ActiveEventView.swift#L825)
  and the entry history both carry the last drink type/size.
- Surface it everywhere the user already is:
  - Top of [ActiveEventView](../SipTrack/Views/Event/ActiveEventView.swift) as a large primary button.
  - Live Activity quick action (already has quick drinks — make "repeat last" the first slot).
  - Watch complication / quick add.
  - Optional: lock-screen / Control Center surface so a drink can be logged without opening the app.
- Large, forgiving tap targets. The UI should get **simpler as BAC rises**, not stay constant.
- Keep the existing rich picker for when the user *wants* to choose something different.

**Acceptance.** From phone-in-pocket to "drink logged" in ≤ 2 taps for a repeat;
1 tap when the app/Live Activity is already foregrounded.

---

## P1 — Proactive nudges ("in 15 min you can drive home") *(agreed)*

**Problem.** All proactive intelligence is currently gated behind
`event.drivingMode` or a `targetBAC`
([ActiveEventView.swift#L235-L269](../SipTrack/Views/Event/ActiveEventView.swift#L235-L269)).
The median user sets neither, so the companion shows a number and says nothing.
The phone is also in a pocket all night — guidance that only appears in-app is invisible.

**Goal.** The app tells you the *moment* something changes, on the lock screen.

**Direction.**
- Use the existing `bacTick` timer + Live Activity to push time-based moments:
  - "You can drive in ~15 min" → then "You're under your limit now."
  - "Time for water — you're rising fast."
  - "Steady pace for 40 min — nice."
- Deliver via Live Activity updates and/or local notifications, not just an
  open-app sheet.
- Drive these from the BAC engine's existing time math
  (`hoursToReduceBAC`, `hoursToZeroBAC`) so the countdown is real, not cosmetic.
- Compute "safe to drive at" once, consistently (see P3), and let both the
  banner and the nudge read the same value.

**Acceptance.** A user who never opens the app during the night still receives
the key moments (can-drive, hydrate, slow-down) on the lock screen.

---

## P2 — "Get home" safety flow *(agreed)*

**Problem.** A real companion helps you leave safely. There is no ride button,
no "share my location/ETA with a friend," and the Danger stage literally says
"seek help" with no action
([IntoxicationStage.swift#L22](../SipTrack/Core/IntoxicationStage.swift#L22)).

**Goal.** At any point, getting home safely is one tap away; at high BAC it is
unmissable.

**Direction.**
- **Ride:** one-tap deep link to a ride app (Uber/Lyft URL scheme), prefilled
  where possible.
- **Check in with a friend:** share current location + "heading home" via the
  system share sheet / Messages.
- **High-BAC safety card:** at the Danger stage, replace the passive blurb with
  an actionable card — alcohol-poisoning symptoms + call emergency services.
- Consider surfacing "Get home" in the bottom bar of the active night and in the
  end-of-night flow.

**Acceptance.** From the active-night screen, "get a ride" and "tell a friend
where I am" are each reachable in one tap; Danger stage shows an actionable
safety card, not just text.

---

## P3 — Correct the "time to X" math *(agreed: fix now)*

Two places compute the same fact differently, so the same screen can contradict
itself. Both should use the user's profile elimination rate (β).

1. **Live Activity hardcodes β = 0.015**
   ([AppState.swift#L233](../SipTrack/State/AppState.swift#L233)) while the
   in-app [DriveWarningBanner](../SipTrack/Views/Event/ActiveEventView.swift#L308)
   uses the profile β → "safe to drive at" differs between lock screen and app.

2. **Hero "time to sober"** calls `hoursToZeroBAC(bac)` with the default neutral
   sex ([ActiveEventView.swift#L472](../SipTrack/Views/Event/ActiveEventView.swift#L472))
   instead of the user's profile.

**Fix.** Route both through the profile-aware overloads
(`eliminationRate(profile:)` / `hoursToZeroBAC(_:profile:)`) so every "time to
drive / time to sober" value on every surface is derived from the same β.

> Status: implemented alongside this doc.

---

## Considered & declined

**Reframing the BAC number to a range / lower precision.** Raised as a
trust/precision concern (the hero shows `0.082%` to three decimals despite a
±20% model CV). **Decision: keep the current single-value display.** The number
is understood internally and by the user as an estimate; a range adds noise
without changing behavior. Not pursued.

---

## Sequencing

1. **P3** — math correctness (small, unblocks honest countdowns). *Done.*
2. **P0** — "Same again" near-zero-tap logging (highest day-to-day value).
3. **P1** — proactive lock-screen nudges (makes the companion proactive).
4. **P2** — get-home safety flow (makes it a companion, not a tracker).
