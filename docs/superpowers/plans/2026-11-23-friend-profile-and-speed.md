# Friend Profile and Faster Friend Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make friend actions feel instant and add a BeReal-style friend profile: big photo, a display name, and a friends-only stats card.

**Architecture:**
- **Speed:** the server loads its heavy SDKs lazily, the app stops forcing an ID-token refresh on every call, and friend actions update the UI optimistically.
- **Display name:** a `name` field on `public_profiles`, set through a new `setDisplayName` callable.
- **Stats:** computed on the owner's phone and written to `profile_stats/{uid}`, which only friends (and the owner) can read. A new `FriendProfileView` shows all of it.

**Tech Stack:** SwiftUI (iOS 18), Firebase Firestore/Functions/Auth, Cloud Functions v2 (Node 24).

**Spec:** docs/superpowers/specs/2026-11-23-friend-profile-and-speed-design.md

## Global Constraints

- iOS 18, Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure helpers are `nonisolated static`. Tests use Swift Testing (`@MainActor struct`, `@testable import siptrack`).
- Every new Swift file needs four `project.pbxproj` entries (PBXBuildFile, PBXFileReference, group `children`, target Sources phase) with fresh unique 24-hex IDs. Prefer adding tests to existing test files.
- No local Xcode: Swift compiles only in CI. Functions: eslint google style, 80 cols, JSDoc, LF; `cd functions && npm run lint && npm test && npm run test:emulator` with `export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr" PATH="/c/Program Files/Android/Android Studio/jbr/bin:$PATH"`.
- Commit messages: one line, no body.
- Any new `defineString`/`defineInt` param needs a value in the committed `functions/.env`, or the deploy aborts. This plan adds none.
- No competitive stats: no max BAC, no records, no streaks, no rankings or comparisons.
- Incognito nights and nights with no drinks never count toward stats.
- Name: trimmed, 1–30 characters, no control characters, checked against the username moderation list; empty clears it.
- `profile_stats/{uid}` keys exactly `nights`, `avg_drinks`, `avg_water`, `favorite_drink` (optional), `member_since`, `updated_at`. The stats window is the last 90 days, except `nights`, which is all time.
- App UI copy is English.

## Review Focus

1. A friend action that fails on the server rolls the row back and shows the existing error, and never leaves it stuck in a fake state. Task 3 owns the tests.
2. Blocking or unfriending removes access to stats: the rules read through `friendships/{owner}/friends/{reader}`. Task 2's rules test.
3. A user with zero eligible nights has no average and doesn't divide by zero: the card shows "No stats yet". Task 4 test.
4. A name with only spaces, emoji only, or 31+ characters: spaces clear the name, emoji are allowed, too long is refused. Task 2 test.
5. Turning "Show my stats to friends" off deletes the doc and stops publishing. Task 4 test (pure decision helper).

---

### Task 1: Lazy-load heavy modules in Cloud Functions

**Files:**
- Modify: `functions/index.js`, the top-level requires at about lines 21–44 and their use sites
- Test: `functions/index.test.js` (or a new `functions/lazy-load.test.js`, picked up by `node --test *.test.js`)

**Interfaces:** Produces no new API; behavior is unchanged.

- [ ] **Step 1: Write a failing test.**
  `test("loading index.js does not load the heavy SDKs")`:
  - require `./index.js` in a fresh process;
  - assert that `require.cache` has no key matching `/@google-cloud\/vision|@anthropic-ai\/sdk|@google\/genai|sharp|app-store-server-library/`.

  Use `child_process.execFileSync(process.execPath, ["-e", "..."])` so the cache is fresh, with Firebase emulator env vars or stubs as `index.test.js` already does for loading index.js. Follow that file's pattern.
- [ ] **Step 2: Run it and see it fail.** `cd functions && node --test lazy-load.test.js`. Expected: FAIL, the cache contains `@google-cloud/vision`.
- [ ] **Step 3: Replace top-level requires with memoized lazy getters.** Replace the requires of `@google-cloud/vision`, `@anthropic-ai/sdk`, `./report-service`, `./purchases`, `./drink-lookup`, `./prompts`, `./recovery/prompt`, `./recovery/plan` and `./recovery/image` with lazy getters, for example `const lazy = (load) => { let m; return () => (m ??= load()); };`, used inside the handlers. Keep `social`, `interactions`, `accounts`, `avatar` and `live-activity` eager only if they don't pull a heavy SDK; check each.
- [ ] **Step 4: Verify.** Run `npm run lint && npm test && npm run test:emulator`. Expected: all pass.
- [ ] **Step 5: Commit.** `git commit -m "Load heavy SDKs lazily so social callables cold-start faster"`

### Task 2: `setDisplayName`, name on profile cards, `profile_stats` rules, deletion

**Files:**
- Modify: `functions/social.js` (`profileCard` adds `name`; new `setDisplayName` and `validateDisplayName`), `functions/username-policy.js` (export the moderation check if it isn't exported yet), `functions/index.js` (new `exports.setDisplayName` with the same options as the other social callables: `enforceAppCheck: true`), `functions/accounts.js` (delete `profile_stats/${uid}`), `firestore.rules` (new `profile_stats/{uid}` block)
- Test: `functions/social.test.js` (unit), `functions/integration/emulator.test.js` (callable and rules)

**Interfaces:**
- Produces: callable `setDisplayName({name: string})` → `{name: string|null}`. `profileCard(doc)` now includes `name: string|null`.
- Produces: `validateDisplayName(raw) -> string|null`. It returns the trimmed name, `null` for empty or whitespace-only, and throws `HttpsError("invalid-argument", "Names can be up to 30 characters.")` when over 30 characters, or `HttpsError("invalid-argument", "Try a different name.")` when moderation flags it or it contains control characters.
- Rules: `profile_stats/{uid}`.
  - read: `request.auth.uid == uid || exists(/databases/$(database)/documents/friendships/$(uid)/friends/$(request.auth.uid))`.
  - write: `request.auth.uid == uid`, with keys limited to `['nights','avg_drinks','avg_water','favorite_drink','member_since','updated_at']`.
    - `nights` must be an int, 0…100000.
    - `avg_drinks` and `avg_water` must be numbers, 0…100.
    - `favorite_drink`, if present, must be a string of at most 40 characters.
    - `member_since` and `updated_at` must be ints.
  - delete: the owner.

- [ ] **Step 1: Write the failing tests.**
  - `validateDisplayName`: `"  Lorenzo Orozco "` → `"Lorenzo Orozco"`; `"   "` → `null`; a 31-character name throws "Names can be up to 30 characters."; `"🍻🍻"` → `"🍻🍻"`; `"a\u0007b"` throws; a moderated word throws.
  - Emulator: `setDisplayName` sets `public_profiles/{uid}.name`; an empty name removes the field; it refuses a caller with no profile ("Pick a username first."); `searchUsers` and `suggestFriends` results include `name`.
  - Rules: the owner writes a valid stats doc; a friend reads it; a non-friend's read is denied; it is denied after unfriending; a write with an extra key or `nights: -1` is denied.
  - Account deletion removes `profile_stats/{uid}`.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** Run `npm run lint && npm test && npm run test:emulator`. Expected: pass.
- [ ] **Step 5: Commit.** `git commit -m "Add display names and friends-only profile stats on the backend"`

### Task 3: App speed: no forced token refresh, optimistic friend actions

**Files:**
- Modify: `Firebase/FirebaseManager.swift` (`callFunction` default `forcingTokenRefresh: false`, about line 945; audit every caller and keep `true` only where fresh claims are required), `SipTrack/Social/FriendsStore.swift` (`sendRequest`, `respond(to:accept:)`, `cancelRequest`), the views that render request and friend rows (`UserSearchView.swift`, `MyFriendsView.swift`, `FriendLinkSheet.swift`, `FriendActionDialogs.swift`; read them to find where the row state comes from)
- Create: a pure helper, either in `SipTrack/Social/FriendsStore.swift` or in a new `SipTrack/Social/PendingFriendActions.swift` (register it)
- Test: `siptrackTests/` (an existing social test file, or a new registered `FriendActionsTests.swift`)

**Interfaces:**
- Produces: `struct PendingFriendActions` (value type), holding the optimistic overrides by uid.
  - `enum Action { case requested, accepted, declined, cancelled }`
  - `mutating func begin(_ action: Action, for uid: String)`
  - `mutating func end(for uid: String)`
  - `func overlay(_ state: RowState, for uid: String) -> RowState`. It maps a pending action onto the row state each view already uses. Read each view's existing row-state enum and reuse it, or add one shared enum if the views duplicate it.
- FriendsStore exposes `@Published private(set) var pending = PendingFriendActions()`.
  - Each action: `begin` → await the callable → `end` (success or failure).
  - Rethrow on failure so the existing alert shows.
  - On success, keep the override until the Firestore listener reflects the change, then `end`. A simple approach is to end on the next listener update that contains the uid in the expected list, or after 10 s.

- [ ] **Step 1: Write failing tests.** `begin(.accepted, for: "u1")` then `overlay(.accept, for: "u1") == .friend`. After `end`, `overlay(.accept, for: "u1") == .accept`. `.requested` overlays `.add` as `.pending`. An unknown uid is unchanged.
- [ ] **Step 2: Implement** the helper, the FriendsStore wiring, the views reading the overlay, and the `callFunction` default change.
- [ ] **Step 3: Self-review.** Check that every friend button disables while its own action is pending (no double taps) and that a failure rolls back.
- [ ] **Step 4: Commit.** `git commit -m "Make friend actions instant and stop refreshing the ID token on every call"`

### Task 4: Profile stats on the phone (compute, publish, opt-out)

**Files:**
- Create: `SipTrack/Social/ProfileStats.swift` (register it)
- Modify: `SipTrack/State/AppState.swift` (trigger the publish after `endEvent`, after incognito changes, in `refreshOnForeground` when stale, and after sign-in), `Firebase/FirebaseManager.swift` (`writeProfileStats(_:)` / `deleteProfileStats()`), `SipTrack/Models/UserProfile.swift` or the existing Social prefs (store `shareStatsWithFriends: Bool`, default `true`), `SipTrack/Views/Social/SocialProfileView.swift` (toggle "Show my stats to friends")
- Test: `siptrackTests/ProfileStatsTests.swift` (new, register it)

**Interfaces:**
- Produces:
  ```swift
  nonisolated struct ProfileStats: Equatable, Sendable {
      var nights: Int; var avgDrinks: Double?; var avgWater: Double?
      var favoriteDrink: String?; var memberSince: Date
      nonisolated static func compute(nights: [NightSummary], memberSince: Date, now: Date) -> ProfileStats
      var firestoreData: [String: Any] { get }   // keys per Global Constraints
  }
  nonisolated struct NightSummary: Equatable, Sendable { var start: Date; var incognito: Bool; var drinks: Int; var waters: Int; var drinkNames: [String] }
  enum ProfileStatsPublisher { nonisolated static func shouldWrite(new: ProfileStats, last: ProfileStats?, enabled: Bool) -> Bool }
  ```
  - `compute`:
    - drops incognito nights and nights with `drinks == 0`;
    - `nights` is the count of the remaining nights, all time;
    - the averages are over the remaining nights with `start >= now - 90 days`, rounded to 1 decimal, or `nil` when there are none;
    - `favoriteDrink` is the most frequent name in that window (ties go to alphabetical order), truncated to 40 characters.
  - `firestoreData` writes `avg_drinks` / `avg_water` as `0` when nil. The card shows "No stats yet" when `nights == 0`.
  - `shouldWrite` is false when `enabled == false` (the caller deletes the doc instead), and false when `new` equals `last` ignoring `updated_at`.
- `memberSince` comes from `Auth.auth().currentUser?.metadata.creationDate` through FirebaseManager.

- [ ] **Step 1: Write failing tests** in ProfileStatsTests:
  - incognito and zero-drink nights are excluded;
  - a 90-day boundary night (exactly 90 days old is included, 91 is not);
  - the average rounds to one decimal (3, 4, 3 → 3.3);
  - no nights → `nights == 0` and nil averages;
  - the favorite tie-break is alphabetical;
  - a 41-character drink name is truncated to 40;
  - `shouldWrite` returns false when disabled or unchanged and true when `nights` changes.
- [ ] **Step 2: Implement** the compute and publisher, plus AppState building `NightSummary` from its events and entries. Reuse how SharedNight counts drinks and waters. Wire the publish, the FirebaseManager write/delete, and the toggle: turning it off calls `deleteProfileStats()`, turning it on publishes.
- [ ] **Step 3: Self-review.** Check that publishing runs off the critical path (in a `Task`, never awaited by UI) and that sign-out stops it.
- [ ] **Step 4: Commit.** `git commit -m "Compute profile stats on the phone and share them with friends only"`

### Task 5: Display name in the app

**Files:**
- Modify: `SipTrack/Social/FeedOrdering.swift` (`FriendProfile` gains `var name: String?`; keep the memberwise init working with a default of `nil`), `Firebase/FirebaseManager.swift` (parse `name` in `friendProfile(_:)` and its sibling about line 1297; new `setDisplayName(_:) async throws -> String?`), `SipTrack/Social/FriendsStore.swift` (parse `name` where it reads profile docs, about line 288), `SipTrack/Views/Social/SocialProfileView.swift` ("Name" field under the photo, saved on submit, inline error copy from the server), `MyFriendsView.swift` and `UserSearchView.swift` rows (name above `@username` when set)
- Test: an existing test file covering FriendProfile parsing, or ProfileStatsTests; add `nameIsParsedAndBlankIsNil` for the row → profile parser via a `nonisolated static` helper.

**Interfaces:** Consumes the Task 2 callable `setDisplayName({name})` → `{name}`. Produces `FriendProfile.name: String?`, used by Task 6.

- [ ] **Step 1: Write a failing test** for the parser: a row with `name: "Lorenzo Orozco"` → `.name == "Lorenzo Orozco"`; a missing or empty name → `nil`.
- [ ] **Step 2: Implement.**
- [ ] **Step 3: Commit.** `git commit -m "Let people set a display name and show it in Social"`

### Task 6: Friend profile screen

**Files:**
- Create: `SipTrack/Views/Social/FriendProfileView.swift` (register it)
- Modify: `SipTrack/Views/Social/FeedPostCard.swift` (tapping the avatar or name opens the profile), `MyFriendsView.swift` (a row opens the profile; the night stays reachable from the profile), `Firebase/FirebaseManager.swift` (`fetchProfileStats(uid:) async throws -> ProfileStats?`, reading `profile_stats/{uid}`; nil when missing)
- Test: `ProfileStatsTests`, adding `firestoreRoundTrip` (`ProfileStats` → `firestoreData` → `ProfileStats(firestore:)` equals the original, ignoring `updated_at`)

**Interfaces:**
- Consumes `ProfileStats` (Task 4), `FriendProfile.name` (Task 5), and the existing `FriendNightView` and `AvatarView`.
- Produces `struct FriendProfileView: View { init(profile: FriendProfile) }` and `ProfileStats.init?(firestore: [String: Any])`.

- [ ] **Step 1: Write the failing round-trip test.**
- [ ] **Step 2: Implement the screen to match the spec sketch.**
  - big photo, 200 pt, using `AvatarView` with a large size;
  - the name (title font), then `@username` (secondary);
  - a stats card with the five rows and the copy from the spec sketch;
  - "No stats yet" when the stats are missing or `nights == 0`;
  - below the card, the friend's night (live / last 24 h) using the existing night views;
  - the report/block menu in the toolbar;
  - pull to refresh re-reads the profile and stats;
  - a short fade/scale-in for the card.
- [ ] **Step 3: Wire navigation from the feed card and My Friends.**
- [ ] **Step 4: Commit.** `git commit -m "Add a BeReal-style friend profile with a stats card"`
