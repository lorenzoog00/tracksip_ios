# CoreHaptics branch — decisions taken during execution

Every call made on the user's behalf while executing
`docs/superpowers/plans/2026-10-27-haptics-core.md`, so none of them is buried in
a scratch file. Each line says what was decided and what it costs if the decision
was wrong. Where a decision contradicted the plan, the plan was the thing that
was wrong — the spec (`docs/superpowers/specs/2026-10-26-night-stories-design.md`)
is the binding authority and the plan only argues from it.

## Environment

1. **Executed with no local compile and no local test run.** This is a Windows
   checkout; `xcodebuild`, `swift` and `swiftc` are all absent. Every verification
   step ran on GitHub CI instead, which compiles and runs the full suite on macOS.
   *Cost if wrong:* nothing — CI turned out to be a stronger gate than a local
   build, and it caught a real break (see 12).
2. **Worked on a branch, not in a worktree.** The app's worktree tool is reserved
   for explicit requests and a manual `git worktree add` would leave state the app
   cannot clean up. `main` was never touched.
3. **Only the branch tip is ever CI-verified.** `ci.yml` sets
   `cancel-in-progress: true`, so each push cancels the previous commit's run.
   Intermediate commits have no green run of their own. Nothing claims otherwise.

## Plan defects found and corrected

4. **Every call-site line number in Task 4 was stale.** Addressed by content
   instead, with a `grep` assertion (zero `FeedbackGenerator` outside the engine)
   as the completion check — stronger than any line number.
5. **`SipTrackApp.swift` has no `scenePhase`.** The plan said to hook one. Used the
   file's existing `.onReceive(UIApplication.didEnterBackgroundNotification)`
   idiom rather than introducing a second lifecycle mechanism for one call.
6. **Task 6's mandated persistence test asserted nothing** — it round-tripped a
   `Set<String>` through Foundation and would pass on an empty repository.
   Replaced with tests against the real persistence path, which is what the
   spec's once-per-night-survives-a-relaunch requirement actually needs.
7. **The storage API the plan named was `private`.** Added typed accessors to
   `DataStore` following its own idiom, keyed `siptrack_ceiling_crossed`, and
   added that key to `clearAllData()`'s hardcoded list so sign-out clears it.
8. **Task 5 would have reintroduced a reverted bug.** The plan said to attach a
   `DragGesture(minimumDistance: 0)` to the drink tile; `DrinkPickerList.swift`
   carries a comment recording that this exact gesture was shipped and reverted
   because it fought the grid's scroll. Driven from `PressableTile`'s `isPressed`
   instead. *Cost if wrong:* the ramp follows press duration rather than drag.
9. **`storyAdvance` scales sharpness, not intensity.** The plan said intensity;
   the spec's pattern table says sharpness, and says "intensity ramping" for
   `peak` and `pour` — so its author was distinguishing the two CoreHaptics
   parameters deliberately. Every story tap now feels equally strong while its
   character goes dull-to-crisp as the BAC jump grows, instead of the app getting
   louder as the night gets worse. Renamed `advanceSharpness`, with the
   vocabulary swept through comments, constants and test names.
10. **Turning haptics off would still have buzzed.** The plan said `play` falls
    back to `UIFeedbackGenerator` whenever `shouldPlay` is false — but that is
    false precisely when the *user switched haptics off*, and the spec makes
    `hapticsEnabled` the app's own reduce-haptics switch because iOS exposes
    none. Now: enabled + hardware → CoreHaptics; enabled, no hardware →
    generators; disabled → silent, whatever the hardware.
11. **The plan never mentioned app-target registration.** Both the app target and
    `siptrackTests` list every Swift file by hand in `project.pbxproj`.
12. **That omission broke CI.** `HapticSpec.swift` was written but never
    registered, and the whole test bundle failed with
    `cannot find 'HapticSpec' in scope`. Worth knowing the asymmetry: an
    unregistered *source* turns CI red, an unregistered *test* leaves CI **green**
    and simply never runs. The project memory note now records both.

## Design calls

13. **The haptics toggle got its own "Feedback" section.** The instruction to put
    it "in the same settings section" as `waterSuggestions` placed a vibration
    control under a droplet-icon "Hydration" heading. That instruction was wrong.
14. **The preference survives a cloud pull.** `applyCloudData` replaces the whole
    profile and rescues exactly one field, so `hapticsEnabled` reverted to `true`
    on every sign-in. Rescued it in the same block. **Not** by adding a Firestore
    key — the plan forbids changing the document shape.
15. **The preference is pushed, not only pulled.** `Haptics` caches it and
    refreshes only in `prepare()`, so a toggle could stay stale until relaunch.
    Added `setEnabled(_:)` and called it from `AppState.updateUserProfile(_:)` —
    the single funnel every profile write passes through — rather than patching
    one caller. Ordered after the write, since `prepare()` re-reads from disk.
16. **The background-start guard reads `UIApplication.shared.applicationState`,
    not a flag.** A flag set by `prepare()` and cleared by `stop()` would default
    to false on a cold launch, where `prepare()` is not guaranteed to have run —
    turning a benign first-tap latency into no haptics at all until the app was
    backgrounded and foregrounded. `.inactive` passes, so a cold-launch first tap
    still works.
17. **The ceiling slider only ticks when its value changes.** `onChanged` fires
    60–120 times a second and the haptic fired unconditionally. Pre-existing, but
    the routing made it heavier: each event now builds a `CHHapticPattern` and a
    player rather than making a cheap UIKit call. The decision lives in
    `HapticSpec.selectionChanged(from:to:)` so it is testable.
18. **The pour's closing tap moved to `addDrink`.** `isPressed` drops both on a
    real release and on a scroll-cancel where no drink is added; a "pour finished"
    tap in the second case would be a lie. One haptic per logged drink now, and
    it is the purpose-built `.pourEnd` rather than a generic thud — which also
    fixed a pre-existing double-buzz on **every** drink across five call paths.
    *Cost if wrong:* every drink lands with a sharper tap, including from the
    Watch; a one-line revert.
19. **The pour buzz starts 120 ms in and ends itself after ~1 s.** The delay means
    a quick tap never starts it, so a tap feels like a tap. The self-bound means
    the buzz never depends on `isPressed` dropping — if the "Pour size" menu holds
    it true, the cost is a second of buzz instead of twenty. *Cost if wrong:* a
    hold longer than ~1.1 s goes silent for the rest of the hold; `peakHold` is
    the constant.
20. **`prepare()` moved from each tile to the enclosing list.** It was per-tile
    when each tile owned a generator; `prepare()` now reads and decodes the
    profile from disk, so a dozen tiles meant a dozen main-thread file reads.
21. **A night that crossed its ceiling while the app was dead is now announced.**
    This is the most consequential fix on the branch and the plan caused it. The
    first observation of a night was unconditionally silent, so: ceiling 0.05,
    BAC 0.04 and rising, iOS evicts the app under memory pressure, user reopens at
    0.07 → the crossing happened, was never announced, and nothing would ever
    announce it. The persisted latch exists precisely to tell "already announced"
    from "already over", and the seeding never consulted it. Fixed with a new pure
    predicate `firstObservationFires`. *Cost if wrong:* a relaunch into an
    unannounced over-ceiling night now buzzes once, up to 10 s after the app
    returns, where nothing buzzed before. **This is the one place on the branch
    where a haptic fires in a situation that was previously silent.**
22. **Zero-tolerance ceilings never fire** (`ceiling > 0.005`). Required by the
    spec and implemented by neither predicate. This turned out to be
    *load-bearing* for 21, not hygiene: ungated, `firstObservationFires` reduces
    to `currentBAC >= 0.0`, true at BAC 0.0 itself — so 21 without this guard
    would have alarmed on the first tick of every novice-tier driving night,
    before a sip. See **Open decisions** below: the boundary is one value too
    aggressive.

## Calls that left things alone

23. **The latch is set even when the buzz was dropped.** `play` returns `Void` and
    drops silently when haptics are off, the app is backgrounded, or the engine
    fails. The plan's own "Out of scope" section already covers this: the pocket
    case "is not solvable with haptics… That needs a local notification." Note the
    loss is slightly wider than that — a foreground user with haptics on can also
    miss it via engine init/start failure. Left, because plumbing success out of
    `play` changes an API four tasks consume and a successful `start()` proves
    nothing about what the user felt.
24. **The `UIFeedbackGenerator` fallback branch is unreachable on shipped
    devices.** The iOS 18 floor means A12 or newer, all of which report
    `supportsHaptics == true`; iPad has no Taptic Engine, so the generators were
    no-ops there too. Left in place, but `.pourEnd`'s missing fallback arm was
    added anyway — it is now the app's most frequent haptic and the table read as
    complete while its most-used entry did nothing.
25. **`HapticSpec.shouldPlay` is now tautological** at all three call sites,
    because each is preceded by a bare `guard isEnabled`. Correct as built, forced
    by 10 plus a frozen `HapticSpec`. The consequence worth knowing: the gate its
    three tests cover is no longer the gate that decides anything at runtime. Filed.
26. **`init(from:)` stayed in an extension.** A reviewer argued its legality from
    SE-0169 and SE-0242 rather than guessing; CI then compiled it. No preemptive
    rewrite of code that works.
27. **`ceiling(for:)` was left not `nonisolated`.** The implementer declined that
    instruction with a reason — the precedent it cited takes only `Bool`s while
    this reads `NightEvent` properties — and was right to decline rather than
    gamble a CI round.
28. **The Swift 6 isolation warnings are pre-existing and project-wide.** Nearly
    charged to this branch; `NightPickerTests` emits the identical warning and
    predates it. Cause is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with
    `SWIFT_VERSION = 5.0`, which keeps them warnings. They become hard build
    errors under the Swift 6 language mode. Filed as its own work.

## Process calls

29. **One task boundary was crossed deliberately.** Task 5's fix round edited
    `AppState.swift` — one line — after Task 4, which owns that file, was already
    reviewed and approved. Opening a seventh task for two lines was worse. Task
    4's reviewed mapping changed afterwards, and this records it.
30. **Tests stopped hard-deleting real data.** The new suite deleted five real
    files in the app container behind an in-memory snapshot that `Cmd-.` or a
    crash skips. Now moved aside to `.testbak` siblings, so a crash leaves the
    data on disk under a visible name. See **Open decisions** for the remaining
    double-interruption window.
31. **`updateLiveActivity` moved inside the cancellation guard** and now takes the
    BAC already computed, so the tick no longer runs the full kinetics model twice
    every ten seconds, and a cancelled task can no longer resurrect a Live
    Activity for a night that just ended.
32. **A dead parameter was removed.** `endContinuous(withTransient:)` had no
    caller passing `true` after 18, so the stories work will not inherit a flag
    that does nothing.
33. **Three comments that had become false were fixed**, and a fourth is still
    wrong — see **Open decisions**. Comments that confidently state something
    untrue are worse than no comment, because the next reader trusts them.
34. **Every fix round closed on the first attempt.** The cap was five per task.
    Nothing was parked, so there is no finding anywhere on this branch left open
    with a justification for not fixing it — except the one below.

## Open decisions for the user

**The `> 0.005` guard is one reachable value too aggressive, and the comment
justifying it is wrong.** `CreateEventView`'s ceiling slider has
`snap = 0.005` and keeps that value rather than nilling it, so **0.005 is the
lowest ceiling a user can deliberately set** — and `0.005 > 0.005` is false, so
that night gets no crossing haptic at any BAC. The banner still appears; only the
haptic is lost. Worse, the comment at `HapticSpec.swift:38-46` justifies the guard
entirely in terms of `LegalBACLimit` and never mentions `targetBAC`, which is the
*first* term of `ceiling(for:)` and lands exactly on the boundary — the same class
of confidently-false comment as 33.

Recommended: change the boundary to `>= 0.005` so only values strictly below it
are suppressed. That is exactly the 0.00 legal tiers the requirement named, and it
honours a deliberate user setting. Plus an honest comment and a test pinning
`ceiling: 0.005 → fires`. Three lines.

Underneath it is a real design question that belongs to the user, not to
execution: **should a zero-tolerance ceiling be suppressed at all, or clamped?**
The codebase's own convention goes the other way — `BACCalculator.drivingThreshold`
is `max(limit, bacFloor)`, with the comment that "comparing against 0 makes
'crossed the limit' untestable, so fall back to the display floor". So the drive
warning *does* fire on a zero-tolerance night while the ceiling haptic now never
will. A novice-tier driver in Australia who logs a drink genuinely is over the
legal limit, which is arguably exactly when a buzz earns its keep.

**The `.testbak` fixture still has one window.** After an interrupted run the
`.testbak` is the only copy, so a second run's `removeItem(backupURL)` destroys
it. One line closes it: `guard FileManager.default.fileExists(atPath: fileURL.path)
else { return }` at the top of `remove()`. Still strictly better than the hard
delete it replaced.

## Cannot be verified without a physical iPhone

CoreHaptics needs hardware and the Simulator reports `supportsHaptics == false`,
so these four are nobody's to close but the user's:

1. `.ceilingCrossed` reads as **two** distinct taps, and the alarm is
   unmistakable against a full-swing story tap (one transient at 0.35/0.90 versus
   two at 1.00/0.90).
2. A quick tap on a drink tile still logs **exactly one** drink, and scrolling
   past a tile still works — `isPressed` dropping on scroll is a premise taken
   from a code comment, never verified.
3. The ceiling haptic does not re-fire after a force-quit mid-night — and, new
   with 21, that a relaunch into an already-over night **does** buzz once.
4. A scroll that begins with a finger resting on a tile past 120 ms produces a
   short hum with no drink logged; and the "Pour size" long-press plays the full
   ~1 s pour ramp before the menu opens. Both may be fine; both should be
   decisions rather than discoveries.

## Filed, not fixed

Out of this plan's scope, each recorded with its reasoning:

- `applyCloudData` resets **eight** other local-only profile fields on every
  sign-in and cloud pull — `bacLimit`, `driverType`, `waterSuggestions`,
  `waterReminderIntervalMinutes`, `notifications`, `liveActivityDrinkIds`,
  `aiReportsUsedThisMonth`, `aiReportMonthKey`. The most consequential thing the
  final review found, pre-existing, and surfaced because this branch added its
  one-field rescue to exactly that block.
- `NotificationPreferences` still uses the synthesized decoder, so it carries the
  same data-loss trap one level down. Not triggered today — no field was added —
  and now documented.
- `DataStore.clearAllData()`'s hardcoded key list, hand-extended again. Complete
  today; the next key will be forgotten the same way and nothing will fail.
- `pruneOldEvents` has no callers anywhere, so aged events are never pruned and
  the crossed-ids set grows with them.
- The pour ramp arithmetic is pure and hardware-free but sits in private view
  constants where no test can reach it. With 25, these two are the branch's real
  architectural debt and a single coherent follow-up: finish moving the
  hardware-free decisions into the pure layer.
- The Swift 6 actor-isolation warnings across the whole test target (28).
