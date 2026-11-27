# Paywall redesign: the hangover plan first

## Why

The owner finds today's paywall dull ("muy mierda") and wants one that sells
everything Tracksip does, with the morning hangover recovery plan as the hero
("lo de la cruda está maravilloso"). Today the paywall leads with a wine glass
icon and "Your drinking habits, understood", then an 8-tile grid that also
lists two features that are actually free.

Success: a free user who opens the paywall sees, before anything else, what a
recovery plan looks like, understands what else Pro adds and what stays free,
and sees the price and renewal terms without hunting for them.

## Goals

- Hero: a recovery plan rendered with the app's own plan view, with real food
  photos from the recovery library, animated on open.
- List every real Pro feature, and only those (checked in code and in
  `functions/report-policy.js`):
  morning recovery plan every morning (free: 3 a month), AI Coach weekly and
  monthly reports, Stats, Calendar, Compare periods, personal Goals, full
  history (free: last 30 days), AI drink lookup (free: 5 a month), PDF export,
  no ads.
- One line naming what stays free: live BAC, Live Activity and widgets,
  friends.
- Price, billing period and renewal terms clear (App Store 3.1.2): price from
  StoreKit only, never hardcoded.
- Restore Purchases, Terms of Use and Privacy Policy links, a visible close
  button on the sheet.

## Non-goals

- No change to StoreKit, purchase, restore, entitlement or transaction logic
  (`StoreManager` untouched; `ProView.purchase()` behaviour unchanged).
- No new products, no price changes, no Lifetime on the paywall (it stays
  hidden as today).
- No per-entry-point tailoring of the hero (all 9 entry points get the same
  screen).

## Anti-goals

- Anything that reads as a drinking competition (guideline 1.4.3): no max or
  peak BAC, no "most drinks", no streaks, no rankings, no record night.
- Invented social proof: no stars, ratings, user counts or quotes. There are
  no real reviews to quote and 71 accounts is too few to show a number.
- Selling free features as Pro (today's grid lists "Custom drinks" and
  "Watch live activity", both free).
- Describing drink lookup as photo recognition: it is a text description.

## Constraints

- SwiftUI, iOS 18, Swift 5 mode, MainActor default isolation; dark-only app
  (`.preferredColorScheme(.dark)`), so no light-mode variant.
- No local Xcode: Swift compiles only in GitHub Actions CI. Prefer editing
  `ProView.swift` over adding files (each new Swift file needs four
  `project.pbxproj` entries). Image assets go in `Assets.xcassets`, which needs
  no project entries.
- UI copy in English.
- Respect Reduce Motion and Dynamic Type up to the largest accessibility size.

## Approaches considered

- **A. The hangover plan first (picked by the owner).** A live plan card on
  top, the other Pro features as moving chips, the "always free" line, then
  plans and the button. Shows the real product and keeps the price close to
  the top.
- **B. Stories.** Full-screen auto-advancing pages with the price pinned at
  the bottom. Most eye-catching, but features hide behind waiting or swiping
  and many people close before page two.
- **C. Night to morning timeline.** Tonight (free), tomorrow morning (Pro,
  hero), this week, all time. Tells the whole story, but the hangover plan
  shares the screen with everything else.

## The design (A)

Top to bottom, free user, sheet presentation:

1. Close (X) at the leading edge, "Restore" at the trailing edge.
2. Hero card: the sample plan (`MorningPlan.sample`) drawn with the app's plan
   components, compact, with 2–3 real recovery-library photos bundled as
   assets. On open its steps check off one by one; with Reduce Motion they
   show already checked.
3. Title "Wake up with a plan", one supporting line, and a small
   "Free: 3 plans a month · Pro: every morning".
4. The other Pro features as chips that drift sideways (static with Reduce
   Motion, wrapping at large text sizes).
5. "Always free: live BAC, Live Activity, widgets and friends."
6. Trust line: "BAC estimated with the Widmark formula." No privacy claim:
   friends can see live nights, so "your nights stay private" would be false.
7. Plan picker: Yearly (best value, monthly equivalent) and Monthly.
8. Button "Continue · {price}/yr" (or /mo). If StoreKit reports an
   introductory offer the user is eligible for, the button and the terms line
   name the trial; otherwise no trial copy appears.
9. "Auto-renews {yearly|monthly} at {price} until canceled. Cancel anytime in
   Settings." Terms of Use · Privacy Policy.

Loading and error states for plans stay as today (spinner; error with Try
Again). The pushed presentation from Profile shows the same screen without the
close button. Pro members keep the membership view, with its feature list
corrected to real Pro features.

## Left to the builder

- Exact animation timing and chip layout.
- Which library photos to bundle (breakfast plus one or two activities), at a
  sensible size.
- Whether the plan card reuses `RecoveryPlanContent` scaled down or a compact
  sibling built from the same parts.
