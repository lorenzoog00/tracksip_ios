# Night Stories — design

## Goal

Turn the end of a night from a stats screen into something the user opens the next
morning and shows somebody. A full-screen, tappable sequence of the night's own
photos, each stamped with the BAC at the moment it was taken, running over the
user's own ceiling line — plus a Pro video export sized for Instagram Stories.

## Problem

The data is already good and the presentation is flat.

`NightStatsSheet` already computes peak BAC, minutes above limit, pace, time to
sober and a timeline. `SummaryView` already has `CalorieEquivalenciesCard`,
`CalFoodCell` and `CalSportCell` — the "that's three pizzas" comparison exists
today. `NightFacts.computeNightFacts` already writes contextual one-liners.

All of it renders as same-size tiles with uppercase labels above numbers. When
every element has equal visual weight nothing stands out, and the brain reads it
as a spreadsheet. Nobody screenshots a spreadsheet.

Two problems, one fix each:

1. **It feels cheap.** Every haptic in the app is `UIImpactFeedbackGenerator`,
   `UINotificationFeedbackGenerator` or `UISelectionFeedbackGenerator` — 13 call
   sites. Those three generators are what every weekend app uses, and unprepared
   they fire ~50 ms after the touch. The lag is the cheapness.
2. **It's boring.** Not for lack of information. For lack of hierarchy and for
   lack of a reason to look twice.

---

## Part 1 — The stories viewer

### Entry point

A new `Route.stories(String)` case is added to the `Route` enum. Two places
reach it:

1. **`SummaryView`** — the main one, a primary action above the existing cards.
   The night ends, you land on the summary, and the timeline is right there.
   First time for a given night the label reads **"Create timeline"**, because
   that press is what pulls the photos; every time after it reads **"See the
   timeline"**. Same button, same place, no wizard behind either.
2. **`CalendarView`** — tap any past night, see its story. Note this entry is
   **Pro-only by construction**: `CalendarView:51` already gates the whole
   screen behind `appState.isPro`. That does not make the feature Pro — free
   users reach the same stories from the summary — it just means the
   browse-any-night convenience rides along with the subscription the user
   already bought.

**`HomeView` is deliberately not an entry.** An earlier draft put a thumbnail on
the recent-nights row to dodge the interstitial; the owner removed it to keep
the surface small. See **Ads** for what that costs.

Free for everyone (see **Pro gating**).

### The look: minimal, and that is a requirement

Stated plainly because it is the easiest thing to lose: **simple and
minimalist**. A card is a photograph with a few things on it, not a dashboard
over a photograph.

What that forbids, concretely:

- No more than four text elements on a card: time, BAC, stage, caption.
- No stat tiles, no badges, no icon rows, no chrome borrowed from
  `NightStatsSheet`. That screen's density is what this feature exists to get
  away from.
- The BAC number is the only element allowed to be large. Everything else is
  small and quiet.
- The spine is a hairline, not a chart: no axis labels, no gridlines, no
  legend. One dashed limit line and one dot.
- Controls appear on touch and fade. Nothing permanent floating over the photo
  except the export button and the segment bar.

When in doubt during implementation, remove the element. The photo and the
number are the product; everything else is scaffolding.

### The card stack

Full-bleed, one card per moment, chronological. Navigation is **tap zones, not
swipe**: left 32% goes back, right 68% goes forward, like Instagram. Swipe down
dismisses.

**No auto-advance in the viewer.** Instagram auto-advances because it's a feed
you're grazing; this is the user's own night and they want to linger on the
good ones. Auto-advance exists only in the exported video. *(My call — one
timer to add if you disagree.)*

Segment bar across the top, one segment per moment: filled for seen, accent for
current, dim for unseen.

### What's on a card

- Time, top left. App mark top right (it ends up in screenshots).
- A kicker line: what this moment is (`Tu pico`, `Tequila ×2`, `Primera chela`).
- The BAC at that timestamp, very large — this is the one element that dominates.
- The stage name, in the stage color from `IntoxicationStage.stage(for:)`.
- The user's own caption, if they wrote one. **Nothing by default** — see Part 3.

BAC at a photo's timestamp is interpolated from the night's existing
`[BACDataPoint]` timeline. `interpolatedBAC(at:sorted:)` already exists, private
to the `SummaryShareCard` struct (`SummaryView.swift:1043`) — extract it to
`Core/` and share it.

### The spine

Every card carries a small BAC curve pinned to the bottom edge, with a dot at
the current moment. It is the thing that makes this not a photo dump: the curve
advancing underneath gives the sequence an arc, and it's the one graphic no
competitor can copy because it's the user's own data.

Three properties of the existing timeline the spine has to respect:

- `BACCalculator` samples every 300 s, so the curve is 5-minute resolution.
  Smooth between samples; do not imply precision that isn't there.
- **The timeline starts at the first drink, not at `event.startTime`**, and runs
  past `event.endTime` until BAC clears. The spine's x-axis is the night's wall
  clock (start → end), so the curve begins flat at zero and the tail past the
  end of the night is cropped.
- `interpolatedBAC` clamps outside the sampled range, so a photo taken before
  the first drink would otherwise read as the first sample's value. **Photos
  before the first drink read 0.000**, explicitly, not the clamped value.

### The limit line

A dashed line across the spine at the user's ceiling, labelled **`TU LÍMITE
0.05`** (or the localized equivalent).

The value comes from `event.targetBAC` — which already exists, is already set by
the user through `GoalCeilingMeter` in `CreateEventView`, and is already used for
warnings (`ActiveEventView:61`) and for grading the night solid/heavy
(`AppState:334`). No new model.

Fallback order:

1. `event.targetBAC` → label "your limit"
2. `event.bacLimit` → label "driving limit"
3. neither → the user's resolved legal limit from `LegalBACLimit`, label
   "driving limit", drawn dimmer than a ceiling the user chose

1 and 2 are mutually exclusive by construction: `CreateEventView:135` clears
`targetBAC` when driving mode is switched on.

**Case 3 is the common night, not an edge case.** `targetBAC` is nil by default
(`CreateEventView:11`), `bacLimit` is only set in driving mode
(`CreateEventView:203`), and nights started from the watch pass nil for both
(`WatchBridge:63`). Everything built on the line has to work with a line the
user never chose, which is why it is drawn dimmer and labelled differently.

**Zero-tolerance countries.** `LegalBACLimit` carries many 0.00 limits (Czechia,
Hungary, Egypt, Indonesia, and the novice/commercial tiers of Germany,
Australia, Brazil, Canada, Italy, New Zealand). When the effective limit is
≤ 0.005, suppress the line and the crossing beat entirely — a dashed line on the
baseline that is "crossed" by the first sip is noise, not drama. Those nights
use peak and time-to-sober as their structural beats instead, and the end card's
honest block states the zero limit plainly rather than reporting a
minutes-above number that would be the whole night.

### Crossing, and not crossing

When a line exists and the curve crosses it, that is the tension beat: the BAC
number turns `AppColors.danger` and the stage label is replaced with "you passed
your limit".

**A night that never crosses is not a story with a missing beat — it's the good
version of the story.** The app already grades it: `AppState:334` returns
"solid" when `peakBAC <= targetBAC`. Those nights get the positive variant —
the peak card says the user stayed under, and the end card's honest block
reports the good number instead of the bad one. One design, two polarities, not
two designs.

### Which moments become cards

Cards are driven by photos, plus up to three synthesized cards so the story
holds together when photos are sparse:

- **Start** — always. Names the ceiling the user set.
- **Every selected photo**, in order.
- **Peak** — only if no selected photo falls within ±10 min of it.
- **End card** — always, and it is the one built to be screenshotted.

A synthesized card with no photo uses a gradient derived from the stage color
rather than a gray box. *(My call.)*

### When the entry point does not appear

Both of these are common, not edge cases:

- **No photos** — permission denied, or granted with nothing in the window. The
  story would be three synthesized cards. Still show the entry point: the curve
  and the end card are worth seeing on their own, and when permission was denied
  the first card carries a one-line offer to enable photos. When permission was
  granted and the window is simply empty, say so plainly and don't offer.
- **Zero-drink nights** — `BACCalculator.integrateBAC` returns `[]` with no
  drinks, so there is no spine, no peak and no stage. Sober nights are already
  first-class elsewhere (`computeNightFacts` rule 6, and `prompts.js` has a
  dedicated sober path). They get a curve-less variant: the photos, the time
  out, and an end card built around the reset rather than the peak.

The entry point is hidden only when there are **neither photos nor drinks** —
there is no night to show.

### The end card

Night name, date, duration. Three stat tiles (drinks, peak, waters). Then two
equal-weight blocks:

- The fun one: the calorie equivalence that `CalFoodCell` already computes —
  "3 pizzas", and the run time from `CalSportCell` to burn it.
- The honest one: minutes above the ceiling or the driving limit, and the time
  they came back under it.

The second block is not optional and it is not smaller than the first. A recap
that only makes a heavy night look aspirational is a problem in App Review and a
problem on its own terms. The counterweight is what lets this feature be fun
without being irresponsible — and it costs nothing, because the number is
already computed.

---

## Part 2 — Where the photos come from

### The query

On first open of the stories for a night, fetch `PHAsset`s with `creationDate`
between `event.startTime` and `event.endTime ?? Date()`. Images **and videos** —
on a night out people shoot more video than stills.

### Filtering the junk

The event window will catch screenshots, memes somebody sent, a photo of a
receipt. Exclude `PHAssetMediaSubtype.photoScreenshot`. Cap the set at 20; if
more survive, keep an even distribution across the night rather than the first
20. *(My call.)*

### Videos — poster frames in v1

A night out produces more clips than stills, so videos are included in the
query. But a card is a still everywhere downstream, and compositing real video
tracks into the export is a materially bigger exporter.

v1: a video contributes its **poster frame**, with a small play badge. Tapping
the badge plays the clip full-screen inside the viewer (muted, looped). The
export uses the poster frame, frozen. *(My call — real video compositing is a
v2 question, and the export is silent anyway.)*

### Curation — after playback, not before it

**Playback starts immediately with everything selected.** Curation is an edit
affordance reachable from inside the viewer, not a gate in front of it.

A mandatory grid on first open would be a permission prompt, a fetch, thumbnail
loads and a confirmation screen standing between the user and their night —
which is precisely the anti-goal below. The selection is persisted per event, so
whatever the user removes stays removed.

### iCloud-optimized assets

The common case on a phone with Optimize Storage is an asset that resolves fine
but whose full-resolution data needs a network fetch
(`PHImageRequestOptions.isNetworkAccessAllowed`). That is a different failure
from "the identifier no longer resolves".

- **Viewer:** request a screen-sized thumbnail with
  `deliveryMode = .opportunistic`, so a degraded image appears immediately and
  sharpens. Playback never waits on the network.
- **Export:** needs full resolution for 1080×1920. Fetch with network access
  allowed and fold the download into the export's existing progress bar.
- **Offline with optimized storage:** the viewer shows whatever degraded image
  is cached. The export refuses with a message naming how many photos need a
  connection — it does not silently ship a blurry video.

### Permissions and privacy

- `NSPhotoLibraryUsageDescription` has to be added; the project has no photo
  usage description today. Wording should say the photos never leave the phone,
  because that is true and it raises grant rates.
- Request read access only. **Limited Library access must work** — the viewer
  degrades to whatever assets were granted, with a line offering to pick more.
- Persist only `PHAsset.localIdentifier`, never image bytes. Nothing is copied
  into the App Group container and nothing is uploaded.
- **The identifiers must not sync to Firestore.** They are device-local, useless
  on another device, and syncing them leaks the shape of the user's library for
  no benefit. Local `AppStorage` JSON only.
- An asset whose identifier no longer resolves (user deleted it) falls back to a
  synthesized gradient card. Do not show an error.

---

## Part 3 — The text on each card

### Decision: nothing by default, the user's words optionally

A card ships clean: photo, time, BAC, stage, spine. No sentence.

The user can add their own caption to any card. Nothing we generate is ever
written onto a card without them choosing it.

The reasoning is that a caption lands on a photograph of real people, and a
sentence the app chose can land wrong in a way a sentence the user chose never
can. "3 tequilas en 40 min" is a great line on the peak card and a tone-deaf
one on a photo of somebody's birthday. The app cannot tell those apart. The
user can, in one second.

It also means the clean card is the honest default: most people will not type
anything, and a wall of photos with a big BAC number over a live curve is
already the thing nobody else has.

### Writing a caption

Tap the lower third of a card → inline text field, keyboard up, type, done.
Empty field renders as no caption at all, not as an empty row.

- Cap around 90 characters so it never climbs over the photo. One or two lines.
- Editable and clearable at any time, including after the video has been
  exported once.
- Captions appear in the exported video exactly as on the card.

### The computed fact as a suggestion, never a default

When the user opens the editor on a card where a fact fired, the fact appears as
a dismissible suggestion chip above the keyboard. One tap inserts it as ordinary
editable text — they can send it as-is, reword it, or ignore it.

This keeps the fact catalog earning its keep without it ever putting words in
the user's mouth. The suggestion is the app being useful; the caption is the
user being themselves.

### The fact catalog

A pure function in `Core/`, in the shape of the existing
`computeNightFacts` — no SwiftUI, no side effects, fully testable:

```
nightStoryFact(at moment:, context:) -> StoryFact?
```

Rules, highest priority first. **Each fires at most once per night**, so the
sequence never repeats itself:

1. First crossing of `targetBAC`
2. The peak
3. Fastest stretch — most ethanol grams in any rolling 30 min
4. Multiple of the ceiling ("2.4× tu techo")
5. Pace against the user's own baseline — defined as the **last 10 finished
   nights with at least one drink**, compared on ethanol grams per hour. Skip
   the rule when fewer than 3 qualify, so new users never see a comparison
   drawn from one night. This aggregate does not exist in `AppState` today and
   has to be computed and passed in as context.
6. Water logged
7. Back under the limit
8. Sober-by time

Calorie equivalence stays on the end card only — it's a whole-night number and
it's the payoff line.

Returning `nil` is a normal outcome: no suggestion chip is offered on that card,
and the user types from scratch or types nothing.

### Where captions are stored

Same place and same rules as the photo selection: local `AppStorage` JSON, keyed
by `PHAsset.localIdentifier` for photo cards and a stable string for synthesized
ones. **Not synced to Firestore.**

A correction worth carrying: the header comment in `Storage/AppStorage.swift`
says the App Group container, but `containerURL` actually resolves to the app's
own `.documentDirectory`, despite `group.lorenzoog.siptrack` being present in
the entitlements. Captions and selections go wherever the existing store goes —
do not "fix" the path as part of this feature.

The caption is bound to a photo that is already device-local, so syncing the
text alone would produce orphaned sentences on another device. Consistency with
the photo rule is also the simpler story to tell the user: what happens in the
stories stays on the phone.

### Not per-photo AI

Worth stating explicitly so nobody adds it later thinking it was an oversight.

The model cannot see the photo unless the photo is uploaded, and uploading is
the one thing this feature must never do. Without the image, a generated caption
reads like *"The night was picking up and the mood was at its best"* — generic
filler, exactly the texture we're removing.

It is also ~10× the cost of a night report (`requestReport` runs
`claude-haiku-5-5` at 700 max tokens, already capped monthly by
`aiReportsUsedThisMonth`), adds a spinner before the user can see anything, and
breaks offline.

### Where AI does belong: the night report the user already has

**No new report kind, no new Cloud Function call, no new budget.**

An earlier draft of this document called for a new `kind: "story"`. That was
wrong and the builder check caught it. It would have meant: a new entry in
`FREE_LIMITS` with a free-cap number nobody has chosen; a mandatory prompt entry
in `prompts.js` (`buildPrompt` reads `labels.length` and would throw on an
unknown kind); unpicking the `max_tokens: 700` that `functions/index.js:81` and
`report-policy.js` assert against each other; a new document type landing in
`users/{uid}/ai_coach_reports` that the client's `ReportType` doesn't decode —
which *is* a Firestore shape change, against this document's own constraint; and
a second call per night that would halve a free user's five monthly reports
against the aggregate `aiReportsUsedThisMonth` counter.

Instead: when the night already has an `aiReport`, the end card shows its
**first sentence**, extracted client-side. Zero backend change, zero extra cost,
nothing new to sync, and it is already gated by `aiReportsEnabled` and the
existing cap because the night report is.

When there is no night report — AI off, over cap, offline, or simply not
generated — the end card shows the top computed fact. The user notices nothing.

If the first sentence turns out to read poorly as a headline, the cheap fix
later is asking the existing night prompt to lead with one line. That is a
prompt edit, still no new kind.

---

## Part 4 — The video export (Pro)

### Shape

1080×1920, H.264 `.mp4`, about 15 seconds, **no audio track**.

### Why silent is a design decision, not a limitation

Shipping commercial music is a copyright strike. Instagram and TikTok both let
the user add a track at upload, which is what people do anyway. Exporting silent
means no licensing exposure and the file drops straight into the normal Stories
flow. The consequence: cuts cannot land on a beat, so the curve has to carry the
visual pulse by itself. That is why the spine animates continuously rather than
cutting per card.

### Structure

A video needs an arc; a chronological dump of cards goes dead around second six.
Timings validated in the prototype:

| Beat | Length | Content |
|---|---|---|
| Title | 2.4 s | Night name, date, curve at zero |
| Moments | ~2.0 s each | Photo, BAC, stage, caption if the user wrote one |
| Ceiling crossing | 2.1 s | Number turns red |
| **Peak** | **2.9 s** | Held longest. Biggest number in the video |
| Relief | 1.9 s | Water, curve descending — closes on an up note |
| End card | 2.2 s | The screenshot target |

Where more moments exist than fit, keep the structural ones (start, crossing,
peak, water, end) and distribute the rest evenly. Cap around 8 beats in the
video even when the viewer shows 20 cards.

### How to render it

`AVMutableComposition` with a blank video track plus
`AVVideoCompositionCoreAnimationTool`, driving a `CALayer` tree; export through
`AVAssetExportSession`. All on-device, no server.

**Correction to an earlier draft.** This document previously claimed the payoff
was that the animated curve is "a `CAShapeLayer` — the same layer that draws on
screen". That is false and the builder check caught it: there is no `CALayer`
anywhere in this app. The UI is pure SwiftUI, the existing chart is Swift Charts
(`BACChartView`), the only `UIViewRepresentable` is the AdMob wrapper, and the
one existing export path is `ImageRenderer` (`NightReportPDF.swift:34`).

**What is actually shared is the geometry, not the layer.** Write one pure
function that turns the BAC timeline into a `CGPath` for a given size. The
on-screen spine stays SwiftUI and renders it as `Path(cgPath:)`; the exporter
hands the same `CGPath` to a `CAShapeLayer` and animates `strokeEnd`. The curve
is defined once; only the two thin drawing shells differ, and the viewer does
not have to be rewritten in UIKit to get it.

The alternative — rasterizing each card with `ImageRenderer` and feeding stills
into the composition — is more consistent with the repo but means ~450 main-actor
renders at 1080×1920 for a 15 s clip. Rejected on cost. *(My call.)*

Run off the main queue, show determinate progress with a cancel, write to
`FileManager.default.temporaryDirectory`, and hand off through the existing
`ShareSheet` in `NightReportPDF.swift:6`.

---

## Part 5 — Haptics

This is problem 1 and it is independent of everything above — it touches the
whole app and should ship first, because it's small and it improves every screen.

### `Core/Haptics.swift`

A `CHHapticEngine` wrapper. Falls back to the current `UIFeedbackGenerator`
calls when `CHHapticEngine.capabilitiesForHardware().supportsHaptics` is false,
so nothing regresses on older hardware.

**Start the engine and prepare patterns ahead of the gesture.** The lag of an
unprepared generator is a large part of why the current haptics feel cheap.

One correction: `DrinkPickerList.swift:301` already calls `haptic.prepare()` on
appear, so that site is not suffering from latency — its problem is that a flat
`.medium` impact is the wrong *shape* for pouring a drink. The latency argument
applies to the sites that don't prepare, which is the rest of them.

Handle `stoppedHandler` and `resetHandler` by restarting; stop the engine on
background.

### Patterns

| Name | Shape | Where |
|---|---|---|
| `storyAdvance` | Light transient, sharpness scaled by BAC delta between cards | Stories tap |
| `ceilingCrossed` | Two sharp transients, unmistakable through a pocket | Stories, **and live** during the night |
| `peak` | 0.25 s continuous, intensity ramping up | Peak card, peak beat |
| `pour` | Continuous while the drink button is held, intensity ramping, transient on release | `DrinkPickerList` |
| `exportDone` | Success | Video export finished |

### `ceilingCrossed` live during the night — two corrections

An earlier draft said "`ActiveEventView:61` already detects
`currentBAC >= targetBAC`". It does not. That line is a **view-render
predicate**, re-evaluated on every `bacTick` — which fires every 10 seconds
(`AppState.startBACRefreshTimer`). Firing a haptic there as written buzzes the
phone every 10 seconds for the rest of the night.

What it needs: edge detection with a persisted `hasCrossedCeiling` flag on the
event, firing **once per night**, never re-armed if the user drops back under
and crosses again. One crossing, one buzz.

The same draft justified this with "at 1 a.m. in a loud bar the user can't read
the screen but can feel the phone". **That justification does not hold** and is
withdrawn: haptics don't play when the app isn't foreground-active, and this
document itself says to stop the engine on background. As specified, the buzz
only reaches a user who is already looking at the screen.

The pocket case is real and worth building — but it is a **local notification**,
not a haptic, and the app already has `WaterReminderManager` and
`LiveActivityManager` to model it on. That is a separate, small follow-up and is
explicitly **out of scope here**, so that Part 5 stays the small piece that
ships first.

### User control

Add a `hapticsEnabled` preference (default on) to `UserProfile`. There is no
public system "reduce haptics" flag to read, so the app needs its own.

---

## Pro gating

The video is Pro. The viewer is free.

A free user taps **Export video**, the video is generated and **plays in full
inside the app**, and the share step raises the paywall —
`showPaywall = true` → `.sheet { ProView(presentation: .modal) }`, matching
`CalendarView` and `ChallengesView`.

Rationale: the strongest moment to ask is after they've seen their own night cut
together and want it, not before. A locked card converts worse than a thing
they're already holding. *(My call, inside the decision that the video is Pro —
if you want it locked before playback instead, it's a one-line change.)*

---

## Ads — unchanged, with one accepted cost

**No ad is removed, delayed, suppressed or added.** Ad behaviour is exactly as
it is today.

First, a correction to how this was originally framed in this document. The
summary you just finished is *already* ad-free: `SummaryView:425` guards the
interstitial with `if appState.pendingSummaryEventId != eventId`, and `endEvent`
sets that id, so the fresh end-of-night summary never fires one. The
interstitial fires only when **browsing a past night**, and only every other
visit.

So the main path — night ends, summary appears, "Create timeline" — has no ad in
it at all. That is the path most of this feature's use runs through.

### The cost being accepted

For a **free** user opening a **past** night: Home → tap the night →
`Route.summary` → interstitial on roughly every other visit → summary →
"See the timeline". The morning-after open sits behind that ad.

An earlier draft dodged this by putting a stories thumbnail on the Home row.
The owner removed it to keep the surface small, which is a legitimate trade:
one fewer entry point against one ad, every other visit, free tier only, past
nights only. Pro users never see it, and the calendar entry is a Pro screen
anyway.

**Do not "fix" this by suppressing the interstitial.** It is revenue and it is
also an argument for Pro.

If it ever does need softening, the cheap move is moving
`showInterstitialForBrowse` from the summary's `onAppear` to its dismissal —
same impressions, just not in front of the thing the user came for. Out of
scope here; noted so nobody has to rediscover it.

## Goals

- The user opens the app the morning after, unprompted.
- Any past night is one tap from its story in the calendar.
- The night's existing data gains hierarchy: one thing dominates each screen.
- The BAC curve becomes the product's signature graphic.
- A Pro hook that lands at the moment of highest want.
- The app stops feeling generic to the hand.

## Non-goals

- Photo editing, filters, stickers.
- Rich text for captions — no fonts, colors, sizing or free positioning. One
  plain line, styled by the app, so every card stays on-brand.
- Music in the export.
- Per-photo AI.
- Sharing between users, or any server-side storage of photos.

## Anti-goals

These make it a failure even if it ships and works:

- **Any photo leaving the device.** The local-only promise is the feature's
  spine as much as the curve is.
- **Any text on a card the user did not choose.** The default is clean. The
  fact catalog offers; it never writes.
- **A spinner before the user can see their night.**
- **A recap that glamorizes a heavy night with no counterweight.** The honest
  number sits on the end card at equal weight, always.

## Constraints

- SwiftUI, existing architecture: `AppState` `@MainActor`, JSON in the App Group
  container, StoreKit 2.
- Everything on-device except the one optional AI line.
- Must work offline and under Limited Photo Library access.
- Must not change the Firestore document shape.
- Copy follows the app's existing language (English today). Keep the fact
  catalog in one file so localization is one place. *(My call — the prototype
  was in Spanish because the conversation was.)*

## Left to the builder

- File layout, view decomposition, and the layer hierarchy for the export.
- Exact easings and transition timings inside the beat lengths given above.
- Threshold tuning for the fact rules (the values above are starting points).
- Test strategy. Note: `siptrackTests` lists files manually — new test files
  must be registered in `project.pbxproj` or they never run.
- Whether the stories viewer is also reachable from `CalendarView` history.

## Calls I made

Listed so they're easy to overrule:

1. Manual advance in the viewer; auto-advance only in the video.
2. Cap 20 photos in the viewer, ~8 beats in the video, even distribution when over.
3. Screenshots excluded from the photo query.
4. Synthesized gradient cards for start/peak/end rather than gray placeholders.
5. Store `localIdentifier` only, never sync it to Firestore.
6. Captions stored the same way — local only, not synced.
7. Caption cap ~90 characters, plain single line.
8. The computed fact is offered as a one-tap suggestion in the caption editor,
   never written to a card on its own.
9. Free playback, Pro share.
10. Copy in English, matching the app.
11. With no ceiling set — the common night — the line falls back to the user's
    resolved legal driving limit, drawn dimmer and labelled differently.
12. Zero-tolerance limits (≤ 0.005) suppress the line and the crossing beat.
13. A night that never crossed gets the positive variant of the same design,
    not a second design.
14. Videos contribute poster frames; clips play in the viewer, frozen in the
    export. Real video compositing is a v2 question.
15. Curation happens inside the viewer after playback starts, never as a gate
    in front of it.
16. The AI line reuses the existing night report's first sentence — no new
    report kind, no backend change.
17. Photos before the first drink read 0.000, not the clamped first sample.
18. Baseline for pace comparison: last 10 finished nights with ≥ 1 drink,
    skipped under 3.
19. The exporter shares a `CGPath`-producing function with the viewer, not a
    layer; the viewer stays SwiftUI.
20. Live `ceilingCrossed` fires once per night via edge detection; the
    pocket/notification case is out of scope here.
21. Two entries only — `SummaryView` (main) and `CalendarView` (a Pro screen
    already). No Home entry; ads stay exactly as they are, and the free
    past-night interstitial is an accepted cost.
22. The summary button reads "Create timeline" the first time for a night and
    "See the timeline" after — one button, no build wizard behind it.
23. Minimal is a hard requirement, with an explicit element budget per card.
