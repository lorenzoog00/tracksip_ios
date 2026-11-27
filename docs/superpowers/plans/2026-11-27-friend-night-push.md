# Friend Night Push Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push "@alex started a night" to a person's friends when their shared night starts.

**Architecture:** A Firestore `onDocumentWritten` trigger on `shared_nights/{uid}` detects a new, open, recent night. A transaction on `night_start_pushes/{uid}` enforces dedupe and a 12 h cooldown. The trigger then fans out over `friendships/{uid}/friends` to recipients whose token has the `"nights"` feature and whose `notification_prefs.friend_nights` is not false. The app adds the feature, a prefs parser and a toggle. The tap reuses the existing `thread` route.

**Tech Stack:** Node 24 Cloud Functions v2 (firebase-functions 7, firebase-admin 14), the Firestore emulator with `node --test`, SwiftUI iOS 18 and Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-27-friend-night-push-design.md`

## Global Constraints

- Copy, exactly: `@${username} started a night`. It must say nothing that invites joining (App Store 1.4.3).
- Cooldown is `12 * 3600000` ms per sender. Freshness is `6 * 3600000` ms from `started_at`.
- The push feature name is `"nights"`. The prefs key is `friend_nights`, and a missing value means on.
- Commit messages are a single line with no body.
- No new `define*` params. Reuse `apnsKey`, `apnsKeyId` and `appleTeamId`.
- No new Swift files, so `project.pbxproj` stays untouched. New code goes into existing compiled files and existing test files.

## Review Focus

- **Doc rewritten on every drink while `started_at` is unchanged:** no push. Covered by the `isNewNight` unit test.
- **Incognito toggled off and back on during the same night** (doc deleted, then recreated with the same `started_at`): no second push. Covered by an emulator test (same `started_at`).
- **Duplicate trigger delivery:** a single push. Covered by running `notifyFriendsOfNight` twice in an emulator test.
- **Recipient on an old app** (features `["threads"]` only): no push, and friend-request pushes still work. Covered by an emulator test.
- **Start time edited forward 30 min:** no second push (cooldown). Covered by an emulator test.

---

### Task 1: Backend trigger logic, rules and deletion

**Files:**
- Create: `functions/night-start.js`, `functions/night-start.test.js`
- Modify: `functions/social.js` (`PUSH_FEATURES`), `functions/accounts.js` (delete `night_start_pushes/{uid}`), `functions/accounts.test.js`, `functions/index.js` (export the trigger), `firestore.rules` (`notification_prefs` keys), `functions/integration/emulator.test.js`

**Interfaces:**
- Produces:
  - `isNewNight(before: object|undefined, after: object|undefined, now: number) => number|null` returns the `started_at` to notify about, or null.
  - `notifyFriendsOfNight({db, uid, startedAt, send, now}) => Promise<{sent: number, skipped: string|null}>`. `send` is `(environment, token, payload) => Promise<{status, reason}>`.
  - Constants `COOLDOWN_MS` and `FRESH_MS`.

- [ ] **Step 1: Write unit tests in `night-start.test.js`.** `isNewNight` returns `started_at` in each of these cases:
  - no `before`;
  - a `before` with a different `started_at`.

  It returns null in each of these cases:
  - no `after`;
  - `after.ended_at` is set;
  - the same `started_at`;
  - `started_at` is more than `FRESH_MS` old;
  - `started_at` is not finite.
- [ ] **Step 2: Write emulator tests.** They use the `seed` helpers already in the file, `registerPushToken` and a fake `send`:
  - Fan-out: friends B and C each get `{aps: {alert: {body: "@alpha started a night"}, sound: "default", "thread-id": "A_T"}, route: "thread", owner: "A", started_at: T}`. Non-friend D gets nothing.
  - Each of these gets nothing: `friend_nights: false`, `features: ["threads"]` only, and no token. A 410 deletes the token.
  - A second call with the same `startedAt` returns `skipped: "duplicate"`. A call with `startedAt + 30 min` inside the cooldown returns `skipped: "cooldown"`. After `now + COOLDOWN_MS + 1` the call sends.
  - No `public_profiles/A` returns `skipped: "no-profile"`. `account_deletions/A` returns `skipped: "deleting"`.
  - Rules: `setDoc(ref, {friend_nights: false})` succeeds, and `{friend_nights: "off"}` fails.
  - Account deletion: add `"night_start_pushes/A"` to both the seeded writes and the gone list.
- [ ] **Step 3: Run `npm test` and `npm run test:emulator`.** They fail because the module is missing.
- [ ] **Step 4: Implement `night-start.js`.**
  - Read `public_profiles` and `account_deletions` before the transaction.
  - The transaction on `night_start_pushes/{uid}` writes `{started_at, sent_at: now}`.
  - Read the friend ids with `listDocuments()` or `get()` on `friendships/{uid}/friends`.
  - Use `db.getAll` in chunks of 100 for the `push_tokens/{fid}` and `notification_prefs/{fid}` refs.
  - Send with `Promise.all`. On a dead token, delete it, using `tokenIsDead` from `live-activity`.
- [ ] **Step 5: Make the other backend edits.**
  - Add `"nights"` to `PUSH_FEATURES`.
  - In the rules, `hasOnly([... 'friend_nights'])` plus a `get('friend_nights', true) is bool` check.
  - In `accounts.js`, delete `night_start_pushes/${uid}` after `notification_prefs`, and update the `docDeletes` lists in `accounts.test.js`.
  - In `index.js`, export `notifyFriendsOfNight = onDocumentWritten({document: "shared_nights/{uid}", secrets: [apnsKey], timeoutSeconds: 120}, ...)`. It returns before building `alertPushClient()` unless `isNewNight` passes, and closes the client in `finally`.
- [ ] **Step 6: Run `npm run lint && npm test && npm run test:emulator`.** All pass.
- [ ] **Step 7: Commit.**

### Task 2: iOS feature, prefs and toggle

**Files:**
- Modify: `SipTrack/Core/PushRegistration.swift` (add `NotificationPrefs`), `Firebase/FirebaseManager.swift` (`pushFeatures`, `notificationPrefs()` return type, comment on `setNotificationPref`), `SipTrack/Views/Social/SocialProfileView.swift` (toggle), `siptrackTests/FriendLinkTests.swift`

**Interfaces:**
- Produces: `nonisolated struct NotificationPrefs: Equatable, Sendable { var reactions, comments, replies, friendNights: Bool; init(data: [String: Any]); static let allOn }`.

- [ ] **Step 1: Write Swift tests in `FriendLinkTests.swift`.**
  - `NotificationPrefs(data: [:]) == .allOn`.
  - `NotificationPrefs(data: ["friend_nights": false]).friendNights == false`, and the other keys stay true.
  - A non-bool value (`"off"`) reads as true.
  - `FirebaseManager.pushFeatures.contains("nights")`.
- [ ] **Step 2: Implement.**
  - `notificationPrefs()` returns `NotificationPrefs`, or `.allOn` when signed out.
  - `SocialProfileView` gets `@State notifyFriendNights = true` and a first row, "Friends starting a night", bound through `prefBinding("friend_nights", ...)`. `loadNotificationPrefs` assigns from the struct.
- [ ] **Step 3: Re-read every changed Swift line for compile errors.** There is no local Xcode: check isolation (`nonisolated` struct), optional handling and tuple-to-struct call sites.
- [ ] **Step 4: Commit.**

### Task 3: PR

- [ ] Push `feat/friend-night-push` and open a PR into `dev`.
- [ ] Bind it with ccd_pr and read CI. Fix until both jobs are green.
