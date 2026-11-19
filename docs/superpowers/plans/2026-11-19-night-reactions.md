# Night Reactions, Comments and Mentions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Friends react (one of six emojis), comment and @mention on each other's shared nights from a new feed post card, with grouped push notifications that open the night's comment sheet.

**Architecture:** All writes go through App Check callables in a new `functions/interactions.js` that keep a per-night summary doc (`night_threads/{owner}_{started_at}`) plus `reactions` and `comments` subcollections, all expiring with the night. The app listens to the summary doc for the feed card, reads the full thread through a block-filtered callable, and replaces `FeedRow` with an animated `FeedPostCard` and a `NightThreadSheet`.

**Tech Stack:** Firebase Functions v2 (Node 24), Firestore rules + TTL, APNs alert pushes; SwiftUI (iOS 18), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-19-night-reactions-design.md`

## Global Constraints

- Branch `feat/night-reactions`, based on `feat/friend-chart-contacts` (PR #53).
- iOS 18 deployment target, Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure helpers called from synchronous tests are `nonisolated static`; test suites touching app types are `@MainActor`. `ObservableObject` files `import Combine`.
- Every new Swift file is registered by hand in `siptrack.xcodeproj/project.pbxproj` (PBXFileReference, PBXBuildFile, group, Sources phase) for its target. Follow the `5F1D0001…` ID pattern with a fresh unique prefix (`6A2E…`).
- Swift compiles only in CI on macOS; locally only the functions are run.
- Functions: eslint google style, max 80 columns, JSDoc on every function. `npm test` (unit) and, with `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"; export PATH="$JAVA_HOME/bin:$PATH"` as separate statements, `npm run test:emulator`.
- Commit messages are a single line, no body.
- Reaction keys, in display order: `beer 🍻, fire 🔥, laugh 😂, woozy 🥴, water 💧, heart ❤️`.
- Comments: text only, trimmed, 1–200 characters, no URLs (`/https?:\/\/|www\./i`), max 50 per person per night, at least 3 s apart.
- Reaction pushes: owner only, at most one per night every 15 min, at most one per reacting person per night.
- `nightKey = "{ownerUid}_{started_at ms}"`.
- Push copy (exact):
  - reaction, one person: `@{from} reacted {emoji} to your night`
  - reaction, grouped: `@{from} and {n} others reacted to your night` (`1 other` when n = 1)
  - comment: `@{from} commented: {text}`
  - reply: `@{from} on @{owner}'s night: {text}` (author is owner: `@{from} replied on their night: {text}`)
  - mention: `@{from} mentioned you on @{owner}'s night: {text}`
  - `{text}` is cut to 80 characters with `…`.
- Notification prefs doc `notification_prefs/{uid}`: `reactions`, `comments`, `replies` booleans, missing = on. Mentions obey `replies`.
- Every animation honours Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): springs become 0.2 s fades, no particles, no drawing.

## Review Focus

- A reaction or comment on a night that ended and was replaced by a new night (same owner, different `started_at`) must be rejected, never land on the new night. → Task 1 test `rejects a stale started_at`.
- Someone unfriended after commenting must not be able to read or write the thread. → Task 1 and Task 2 tests `ex-friend cannot react/comment`, rules test in Task 3.
- A comment that mentions the same person twice, mentions the author, or mentions someone who cannot see the night must push nobody extra. → Task 2 test `mentions are deduped and limited to viewers`.
- Rapid double-tap on a reaction (toggle on/off/on) must leave counts consistent and never negative. → Task 1 test `counts never go negative`; Task 4 test `toggle math`.
- Going incognito mid-night must remove the thread for friends at once. → Task 3 trigger test.

---

### Task 1: Reactions backend

**Files:**
- Create: `functions/interactions.js`
- Test: `functions/integration/emulator.test.js` (append a `// interactions: reactions` block)

**Interfaces:**
- Produces (exported from `interactions.js`):
  - `REACTIONS = {beer: "🍻", fire: "🔥", laugh: "😂", woozy: "🥴", water: "💧", heart: "❤️"}`
  - `nightKey(owner: string, startedAt: number) -> string`
  - `loadNight({db, owner, startedAt, uid, now}) -> Promise<{night, ownerName, viewerName}>` — throws `HttpsError`: `not-found` "This night is no longer available." when `shared_nights/{owner}` is missing, its `started_at` differs, or `expires_at` ≤ now; `permission-denied` "You can't see this night." when uid is neither owner nor in `friendships/{owner}/friends`, or a block exists either way; `failed-precondition` "Pick a username first." when the caller has no profile.
  - `reactToNight({db, uid, data: {owner, startedAt, emoji}, notify, now = Date.now()}) -> Promise<{emoji: ?string}>`
  - `notify(toUid, kind, payload)` where `kind ∈ {"reaction","comment","reply","mention"}` and `payload = {from, owner, ownerName, startedAt, emoji?, others?, text?}` — implemented in Task 3; tests inject a recorder.

- [ ] **Step 1: Write failing emulator tests**
  - `reacting sets one reaction and counts`: B (friend of A) reacts `beer` → `night_threads/A_{t}` has `reactions.beer == 1`, `reactors == ["B"]`, `expires_at` equals the shared night's; `reactions/B` has `{emoji: "beer", username: "bobby"}`.
  - `changing reaction moves the count; same emoji removes`: beer → fire gives `{beer: 0 or absent, fire: 1}`; fire again → no doc `reactions/B`, `fire` 0/absent, `reactors` without B.
  - `counts never go negative`: remove twice in a row → counts ≥ 0, no throw.
  - `owner cannot react`, `ex-friend cannot react`, `blocked either way cannot react` → `permission-denied`; unknown emoji → `invalid-argument`.
  - `rejects a stale started_at` and expired night → `not-found`.
  - `reaction pushes are grouped`: with `now` 0, B reacts → notify `["A","reaction",{from:"bobby", emoji:"🍻", others:0,…}]`; C reacts at +1 min → no push; D reacts at +16 min → `["A","reaction",{from:"dina", others:1}]`; B changes reaction at +40 min → no push (B already triggered one).
- [ ] **Step 2: Run** `npm run test:emulator` — new tests FAIL (module missing).
- [ ] **Step 3: Implement** `nightKey`, `loadNight`, `reactToNight` in `interactions.js`. One transaction reads the summary and `reactions/{uid}`, writes both. Summary fields: `owner, started_at, expires_at, reactions, reactors (≤50, newest last), comment_count, latest_comments, last_reaction_push_at, reactions_since_push, pushed_reactors (≤50)`. Push decision is made inside the transaction (`now - last_reaction_push_at ≥ 15 min` and uid not in `pushed_reactors`, and the change adds or switches a reaction); the push itself is sent after commit through `notify`, wrapped so a failure is logged and swallowed.
- [ ] **Step 4: Run** `npm run test:emulator` and `npx eslint interactions.js` — all pass.
- [ ] **Step 5: Commit** `Add reactToNight with grouped reaction pushes`

### Task 2: Comments backend

**Files:**
- Modify: `functions/interactions.js`
- Test: `functions/integration/emulator.test.js` (`// interactions: comments`)

**Interfaces:**
- Consumes: `loadNight`, `nightKey` (Task 1).
- Produces:
  - `addComment({db, uid, data: {owner, startedAt, text}, notify, now}) -> Promise<{id, text, mentions: [{uid, username}], at}>`
  - `deleteComment({db, uid, data: {owner, startedAt, commentId}}) -> Promise<{status: "deleted"}>`
  - `getNightThread({db, uid, data: {owner, startedAt}}) -> Promise<{reactions: [{uid, username, emoji, at}], comments: [{id, uid, username, text, mentions, at}]}>` oldest first.
  - Comment doc: `{uid, username, text, mentions: [{uid, username}], at, expires_at}`; summary `comment_count` and `latest_comments` (last 3 `{id, uid, username, text, at}`).

- [ ] **Step 1: Write failing emulator tests**
  - `adds a comment and updates the summary`: text `"  hola  "` stored as `"hola"`, `comment_count 1`, `latest_comments[0].text == "hola"`.
  - `rejects empty, 201 chars and links` → `invalid-argument` ("Write a comment first.", "Comments are 200 characters at most.", "Links aren't allowed in comments.").
  - `rate limits`: second comment 1 s later → `resource-exhausted` "Slow down a little."; 51st comment (3 s apart) → `resource-exhausted` "That's the comment limit for this night.".
  - `owner may comment; ex-friend may not`.
  - `pushes`: A's night; B comments → `["A","comment",…]`; C comments → `["A","comment"]` and `["B","reply"]`; A comments → `["B","reply"]`, `["C","reply"]` (author is owner).
  - `mentions are deduped and limited to viewers`: C writes `"@bobby @bobby @zed @carla hey"` where bobby is A's friend, zed exists but is not A's friend, carla is C → stored mentions `[{uid:"B", username:"bobby"}]`; B gets one `mention` push and no `reply`.
  - `notification prefs are respected` is covered in Task 3; here `notify` is called regardless.
  - `delete`: author deletes own; owner deletes anyone's; third friend → `permission-denied`; summary count and latest list update.
  - `getNightThread hides blocks both ways`: D blocked C → D's thread has no C comments/reactions; C's thread has no D's.
- [ ] **Step 2: Run** `npm run test:emulator` — FAIL.
- [ ] **Step 3: Implement** the three functions. Mentions: `/@([a-z0-9._]{3,20})/g` on the lowercased text, resolve through `usernames/{name}`, keep owner or uids in `friendships/{owner}/friends`, drop the author, dedupe. Rate-limit state lives on `night_threads/{key}/limits/{uid}` `{count, last_at}` inside the same transaction.
- [ ] **Step 4: Run** tests and eslint — pass.
- [ ] **Step 5: Commit** `Add comments, mentions and block-filtered thread reads`

### Task 3: Wiring — callables, pushes, prefs, rules, cleanup

**Files:**
- Modify: `functions/index.js`, `functions/social.js` (push copy), `functions/accounts.js`, `firestore.rules`, `firestore.indexes.json`
- Test: `functions/integration/emulator.test.js`, `functions/accounts.test.js`

**Interfaces:**
- Consumes: Task 1–2 exports.
- Produces:
  - Callables `reactToNight`, `addComment`, `deleteComment`, `getNightThread` (App Check, auth required; the first two carry `apnsKey`).
  - `notifyThread({db, send}) -> (toUid, kind, payload) => Promise` in `interactions.js`: reads `notification_prefs/{toUid}` (`reaction`→`reactions`, `comment`→`comments`, `reply`/`mention`→`replies`; missing = on) and `push_tokens/{toUid}`, sends `{aps: {alert: {body}, sound: "default"}, route: "thread", owner, started_at}` with the exact copy from Global Constraints, deletes dead tokens.
  - Trigger `cleanupThreads = onDocumentDeleted("shared_nights/{uid}")` → `recursiveDelete` of every `night_threads` doc where `owner == uid`.

- [ ] **Step 1: Write failing tests**
  - `notifyThread copy and route` for all five copy forms, including `1 other` and the 80-char cut.
  - `prefs off skips the push` for each switch.
  - Rules (emulator, client SDK): friend can `get` the summary and `list` comments of a live night; stranger and ex-friend cannot; nobody can write; owner reads/writes own `notification_prefs` with only the three boolean keys; others cannot read it.
  - Trigger logic exported as `deleteThreadsFor({db, uid})`: deleting removes summary and subcollections.
  - `accounts.test.js`: deletion also calls `notification_prefs/u1` delete and removes the user's `reactions`/`comments` via collection-group `uid` queries.
- [ ] **Step 2: Run** both suites — FAIL.
- [ ] **Step 3: Implement**. Rules: `match /night_threads/{key}` with `function threadOwner() { return key.split('_')[0]; }`, read if `request.auth.uid == threadOwner()` or `exists(friendships/threadOwner()/friends/request.auth.uid)`, and `resource.data.expires_at > request.time` on the summary; subcollections `reactions`, `comments` readable under the same owner/friend check, `limits` never. Indexes: TTL on `expires_at` for `night_threads`, `reactions`, `comments`; COLLECTION_GROUP ascending on `uid` for `reactions` and `comments`.
- [ ] **Step 4: Run** `npm test`, `npm run test:emulator`, `npx eslint .` — pass. Run `node ../scripts/smoke-test-functions.test.cjs` if it enumerates exports.
- [ ] **Step 5: Commit** `Wire reaction and comment callables, thread pushes, prefs, rules and cleanup`

### Task 4: App models and thread store

**Files:**
- Create: `SipTrack/Social/NightThread.swift`, `SipTrack/Social/NightThreadStore.swift`
- Modify: `Firebase/FirebaseManager.swift`, `siptrack.xcodeproj/project.pbxproj`
- Test: Create `siptrackTests/NightThreadTests.swift` (register in the test target)

**Interfaces:**
- Produces:
  - `enum Reaction: String, CaseIterable, Identifiable { case beer, fire, laugh, woozy, water, heart; var emoji: String }`
  - `struct NightKey: Hashable { owner: String; startedAt: Int64; var id: String }` and `init(owner:night:)` from `SharedNight`.
  - `struct ThreadComment: Identifiable, Equatable { id, uid, username, text, mentions: [ThreadMention], at: Date; var isPending: Bool }`, `struct ThreadMention: Equatable { uid, username }`
  - `struct ThreadSummary: Equatable { counts: [Reaction: Int]; reactors: [String]; commentCount: Int; latest: [ThreadComment]; nonisolated static func parse(_ data: [String: Any]) -> ThreadSummary? }`
  - `nonisolated static func ReactionMath.apply(counts: [Reaction: Int], old: Reaction?, new: Reaction?) -> [Reaction: Int]` (never negative, zero entries removed)
  - `nonisolated enum MentionText { static func activeQuery(in text: String, cursor: Int) -> String?; static func segments(_ text: String, mentions: [ThreadMention]) -> [(String, Bool)] }`
  - `FirebaseManager.reactToNight(_ key: NightKey, reaction: Reaction?)`, `.addComment(_ key: NightKey, text: String) -> ThreadComment`, `.deleteComment(_ key: NightKey, id: String)`, `.nightThread(_ key: NightKey) -> (reactions: [(uid: String, username: String, reaction: Reaction)], comments: [ThreadComment])`
  - `@MainActor final class NightThreadStore: ObservableObject` — `init(key: NightKey, myUid: String)`, `@Published summary: ThreadSummary`, `@Published myReaction: Reaction?`, `@Published comments: [ThreadComment]`, `@Published reactedNames: [String]`, `func react(_ r: Reaction) async` (toggle; optimistic, rollback + notice on error), `func send(_ text: String) async` (optimistic pending comment), `func delete(_ comment: ThreadComment) async`, `func refresh() async`, `func start()`, `func stop()`. A shared `NightThreadStore.cache` keyed by `NightKey` so the card and the sheet share one store.
- [ ] **Step 1: Write failing tests** in `NightThreadTests`: `toggle math` (nil→beer, beer→fire, fire→nil, never negative), `summary parse` (numbers as Int/Double, unknown reaction keys ignored, missing fields → zero), `activeQuery` (`"hey @bo|"` → `"bo"`, `"a@b"` → nil, `"@"` → `""`, after a space → nil), `segments` highlights only names present in `mentions`.
- [ ] **Step 2: Implement** the types and helpers; store listens to `night_threads/{key.id}` and `night_threads/{key.id}/reactions/{myUid}`.
- [ ] **Step 3: Register files** in `project.pbxproj`; check with `grep -c "NightThread" siptrack.xcodeproj/project.pbxproj` (expect 3 files × 4 entries for app files, 4 for the test file).
- [ ] **Step 4: Commit** `Add night thread models, store and Firebase calls`

### Task 5: Feed post card and your own night on top

**Files:**
- Create: `SipTrack/Views/Social/FeedPostCard.swift`, `SipTrack/Views/Social/ReactionBar.swift`
- Modify: `SipTrack/Views/Social/FeedView.swift` (remove `FeedRow`), `SipTrack/Social/FriendsStore.swift` (my own night), `SipTrack/Social/FeedOrdering.swift` (`DrinkSummary`), `project.pbxproj`
- Test: `siptrackTests/NightThreadTests.swift`

**Interfaces:**
- Consumes: `NightThreadStore`, `Reaction`, `NightKey` (Task 4); `NightBACChartData(shared:now:)` (PR #53).
- Produces:
  - `nonisolated enum DrinkSummary { static func chips(_ drinks: [SharedDrink]) -> [(name: String, icon: String, count: Int)] }` — grouped by name, ordered by count desc then first time; water is not in `SharedDrink`, so no water chip.
  - `FriendsStore.myNight: FeedItem?` from a listener on `shared_nights/{myUid}` (only while it parses and has not expired).
  - `FeedPostCard(item: FeedItem, now: Date, isMine: Bool, onOpenThread: () -> Void, onOpenNight: () -> Void)`
  - `ReactionBar(store: NightThreadStore, canReact: Bool)` — counts for reactions with count > 0 in `Reaction.allCases` order, yours highlighted, a `+` button; long-press on `+` or a bar fans out `ReactionPicker`.
- [ ] **Step 1: Failing test** `drink chips`: `[Beer, Beer, Tequila, Beer, Wine]` → `[("Beer",3), ("Tequila",1), ("Wine",1)]` with Tequila before Wine (earlier).
- [ ] **Step 2: Implement** the card per the spec's feed card row and Motion section: header (avatar, `@username` or "You", Live · duration / Ended · duration), BAC now or peak with stage colour, a 44 pt mini curve from `NightBACChartData(shared:now:)` drawn with `.trim` animation on appear, chips cascading (`.transition(.scale.combined(with: .opacity))`, 40 ms stagger), "Last: {drink} · {ago}", `ReactionBar` (hidden reacting for `isMine`), comment count button, latest visible comment (filtered against `friends.blocked`) with `.contentTransition(.opacity)`. Live cards keep the green border and breathing `LiveDot`. Haptics through `Haptics.shared.play(.selection)` on react.
- [ ] **Step 3: FeedView**: order = your own night (if any) → "Live now" → "Last 24 hours"; card body tap pushes `FriendNightView`; 💬 presents the sheet (Task 6) via a `@State var thread: NightKey?`. Empty states unchanged.
- [ ] **Step 4: Register files**, commit `Replace feed rows with post cards and put your own night on top`

### Task 6: Comment sheet with mentions

**Files:**
- Create: `SipTrack/Views/Social/NightThreadSheet.swift`
- Modify: `SipTrack/Views/Social/FriendNightView.swift` (reactions + "View comments" row), `project.pbxproj`

**Interfaces:**
- Consumes: Task 4 store and `MentionText`; `ReactionPicker` from Task 5; `ReportBlockMenu`/report flow from `FriendActionDialogs.swift`.
- Produces: `NightThreadSheet(key: NightKey, ownerName: String)` presented with `.presentationDetents([.medium, .large])`.
- [ ] **Step 1: Implement**: header with the six reactions (yours marked "yours"; hidden for your own night) and "Reacted: …"; comment list (avatar, @name, relative time, text with mention pills from `MentionText.segments`), pending comments at 0.6 opacity, insertion `.move(edge: .bottom).combined(with: .opacity)`; long-press menu: Delete (author or owner), Report (others); composer with live character count from 180, Send disabled when empty or > 200; typing `@` shows suggestions (owner, reactors, commenters, and `friends.friends` — server decides who is valid) sliding up above the keyboard; picking inserts `@name `. Poll `store.refresh()` every 5 s while visible.
- [ ] **Step 2: Register file**, commit `Add the night comment sheet with mentions`

### Task 7: Push route, notification switches, docs

**Files:**
- Modify: `SipTrack/Core/PushRegistration.swift` (`PushRoute.thread(owner: String, startedAt: Int64)`), `SipTrack/SipTrackApp.swift`, `SipTrack/State/AppState.swift` (`@Published var pendingThread: NightKey?`), `SipTrack/Views/Social/SocialRootView.swift` (present the sheet when set, switching to Social), `SipTrack/Views/Social/SocialProfileView.swift` (Notifications section), `Firebase/FirebaseManager.swift` (`notificationPrefs()`, `setNotificationPref(_:on:)`), `docs/APP-REVIEW-NOTES.md`, `docs/RELEASE.md`
- Test: `siptrackTests/FriendLinkTests.swift` (`pushRoutes`)
- [ ] **Step 1: Failing test**: `PushRoute(userInfo: ["route": "thread", "owner": "A", "started_at": 1700000000000])` → `.thread(owner: "A", startedAt: 1700000000000)`; missing owner → `.social`; `started_at` as Double works.
- [ ] **Step 2: Implement** the route; tap sets `appState.selectedTab = .social` and `pendingThread`; the sheet opens once Social is on screen (same cold-launch wait as friend links). Notifications section: three `Toggle`s "Reactions on your night", "Comments on your night", "Replies and mentions", reading/writing `notification_prefs/{uid}` with merge.
- [ ] **Step 3: Docs**: App Review notes gain comments/reactions moderation (report, block, 200 chars, expiry); RELEASE checklist gains "deploy functions + rules + indexes before the build".
- [ ] **Step 4: Commit** `Open threads from pushes and add notification switches`

### Task 8: Ship check

- [ ] Push the branch, open the PR against `feat/friend-chart-contacts` (or `main` once #53 merges), wait for CI (`Backend and security rules`, `Build & test (iOS Simulator)`), fix failures.
- [ ] Whole-branch review against the spec; fix findings; re-run CI.
