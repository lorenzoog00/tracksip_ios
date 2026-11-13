# Friends v1 — design

Decided in a grilling session on 2026-11-12. Scope is deliberately small:
see which friends are on a live night and their BAC, and look back at their
nights for 24 hours.

## Product decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | How friends are found | **Username search**, mutual request → accept |
| 2 | Profile contents | **Photo + username + live BAC when on a night.** No history |
| 2b | Who sees what | Search shows username + photo to any signed-in user. Night state and BAC only to accepted friends |
| 3 | When a night is shared | **Automatically** with all friends, unless the night is incognito (see 12) |
| 4 | What a shared night shows | **BAC curve + condensed drink timeline** (icon, name, time), peak, duration, drink count. No photos. Never notes, driving mode or BAC limit |
| 5 | 24 h window | Starts **when the night is closed**. Safety cap: a night still open 24 h after its last drink drops out of the feed and stops sharing |
| 5b | Feed layout | One feed: **live nights on top** with a subtle green treatment, **nights closed in the last 24 h** below |
| 6 | Where it lives | Superseded by 14 |
| 7 | Pricing | **Free**, all of it |
| 8 | When username is chosen | **First time Friends is opened.** Username required, photo optional (initials + colour avatar otherwise) |
| 8b | Username rules | 3–20 chars, `a-z 0-9 . _`, stored lowercase, unique, changeable in Profile (old name freed), blocklist |
| 9 | Push notifications | **Only** "sent you a request" and "accepted your request" |
| 10 | Leaderboard | **Not in v1.** If revisited: weekly, responsibility metrics only — never peak BAC or drink count (guideline 1.4.3) |
| 11 | Photo moderation | **Cloud Vision SafeSearch on upload**; photo invisible until it passes. Plus report + block |
| 12 | Incognito | Toggle "🕶 Incognito" on the **create-night sheet**, off by default, switchable mid-night from the active night. Friends see **nothing** — no live, no 24 h story, no "incognito" badge. Turning it on deletes `shared_nights/{uid}` at once; turning it off shares the whole night including earlier drinks. Settings switch becomes **"Incognito by default"** (replaces "Share with friends") |
| 13 | Managing friends | **My friends** screen: search bar on top (results → Add → Pending), Requests (Accept / ✕), friends list (photo, @username, green dot if live; swipe left = Remove; "⋯" = Remove / Block / Report), Blocked collapsed at the bottom with Unblock. Remove: one confirm, no notice to the other side. Block: confirm that explains the effect. Report: pick username or photo, then offer to block. Empty feed shows a big "Add a friend" button that opens search |
| 14 | Navigation | **Bottom tab bar: 🏠 Home \| 👥 Social.** Each tab keeps its own navigation state. 👥 carries the request badge and a green dot when a friend is live (replaces the Home pill). Social root = the **feed**; top bar has 🔍 search on the left and your **avatar** on the right → your profile (photo, username, edit, Incognito by default, link to My friends) |

## Out of scope for v1

Photos in nights, leaderboard, per-friend sharing, "X started a night" push, BAC threshold
alerts, per-friend or per-night sharing controls, contacts import, invite
links.

## Data model (Firestore)

All new top-level collections; `users/{uid}` stays owner-only.

- `usernames/{name}` → `{uid}`. Written only by the `claimUsername`
  callable inside a transaction (uniqueness, format, blocklist, frees the
  old name on change).
- `public_profiles/{uid}` → `{username, photo_url?, avatar_color}`.
  Readable by any signed-in user (prefix search on `username`). Written
  only by the backend: `claimUsername`, and the photo function after
  SafeSearch passes.
- `friend_requests/{fromUid}_{toUid}` → `{from, to, created_at}`. Created
  by the `sendFriendRequest` callable (rejects if either side blocked, or
  already friends, or a request is pending the other way — that one is
  accepted instead). Readable by `from` and `to`.
- `friendships/{uid}/friends/{friendUid}` → `{since}`. Written on both
  sides by `respondToFriendRequest` / removed by `removeFriend`.
- `blocks/{uid}/blocked/{otherUid}`. Blocking also removes the friendship
  and any pending request, and hides each from the other's search.
- `reports/{id}` → `{reporter, target_uid, kind: username|photo, created_at}`.
  Triggers an email to the developer (Apple expects action within 24 h).
- `shared_nights/{uid}` — **one doc per user**, the current or most recent
  night:
  `{started_at, ended_at?, last_drink_at, expires_at, samples: [BAC every 5 min], drinks: [{name, icon, at}]}`.
  - Written by the owning client directly, schema-checked in rules like
    `night_events`. Never written for an incognito night; deleted the
    moment a night goes incognito.
  - `expires_at` = `last_drink_at + 24h` while open, `ended_at + 24h` once
    closed.
  - Read rule: `exists(friendships/{uid}/friends/{request.auth.uid})`
    **and** `resource.data.expires_at > request.time`, so the 24 h limit
    is enforced by rules, not just hidden by the UI.
  - Firestore TTL policy on `expires_at` does the actual delete.
  - A new night overwrites the previous one's story even inside its 24 h.
    Accepted for v1.

Friends compute "BAC now" by interpolating `samples`, the same way
`functions/live-activity.js` does. No BAC maths server-side, so a friend
sees exactly the curve the owner's app shows.

## Client work

- Upload `shared_nights/{uid}` on every change to the active night (drink
  added/edited/removed, night closed), independent of whether a Live
  Activity exists. Reuse the curve the Live Activity sync already builds.
- Root becomes a `TabView` (🏠 Home | 👥 Social), each tab with its own
  `NavigationStack`. The existing `Route` stack moves under Home
  unchanged. Deep links (`pendingSummaryEventId`, `pendingEventRoute`)
  must switch to the Home tab first.
- Social tab: feed (live + last 24 h), search, social profile, My friends
  (requests, list, remove / block / report, blocked list).
- First-run sheet when Social is first opened: choose username, optional
  photo.
- Incognito: toggle on the create-night sheet and on the active night;
  "Incognito by default" in the social profile. Stored on the night
  (`incognito` field on `night_events` — add to the rules allowlist).
- Friend night detail: BAC curve + drink timeline (borrow the visual
  language of `StoriesView`, not its code — that view reads local data).
- **Remote push registration is new.** The app registers no device token
  today (only Live Activity push tokens). Needs the notification
  permission prompt — ask it when the user sends or receives their first
  request, not at launch.

## Backend work

Callables: `claimUsername`, `sendFriendRequest`, `respondToFriendRequest`,
`removeFriend`, `blockUser`, `reportUser`, `registerPushToken`.
Storage trigger: SafeSearch on uploaded avatar → set `photo_url` or delete.
Push sender for the two request notifications.

**CI never deploys Cloud Functions** — deploy them by hand and check
`firebase functions:list` before shipping the client.

## Account deletion

`deleteAccount` must also remove: `public_profiles`, the `usernames`
entry, both sides of every friendship, pending requests in both
directions, blocks, `shared_nights`, push tokens, and the avatar in
Storage.

## App Store

- Guideline 1.2: report, block, and upload filter are all present — say
  so in `docs/APP-REVIEW-NOTES.md`.
- App Privacy label and privacy policy: add username, profile photo, and
  the 24 h sharing of drink/BAC data with friends.
- Add a demo account with at least one friend for review.
