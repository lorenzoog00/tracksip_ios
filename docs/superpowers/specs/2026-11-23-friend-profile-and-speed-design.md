# Friend profile (BeReal style) and faster friend actions

Status: approved by the owner on 2026-11-23 ("sí, opción 1, dale").

## Why

- Accepting a friend feels slow. Cloud Logging (Nov 2026) shows friend
  callables take 0.2–0.5 s warm but 3–5 s on a cold start, and the app adds a
  forced ID-token refresh before every call and then waits for the Firestore
  listener before the row changes.
- Friends can't see who someone is beyond an @username and a small avatar.
  The owner wants a BeReal-style profile: big photo, a real name, and a card of
  stats about their nights — safe stats only, visible to friends only.

## Goals

1. Friend actions (send, accept, decline, cancel) feel instant.
2. Cold starts of the social callables drop from ~4 s toward ~1 s, at no
   extra monthly cost.
3. A "Name" (display name) people set in their Social profile, shown big on
   their profile with the @username under it.
4. Tapping a friend (feed card avatar/name, or a row in My Friends) opens their
   profile: big photo, name, @username, a stats card, then their current or
   last-24-h night as today.
5. Stats are computed on the owner's phone and published where only friends
   (and the owner) can read them.

## Non-goals

- Keeping functions always warm (minInstances). Revisit only if cold starts
  are still slow after the lazy-loading change.
- Server-side stats computation (option 2), comments on profiles, follower
  counts, any public stats.
- Showing stats to non-friends or in search.

## Anti-goals

- Anything that reads as a drinking competition (App Store 1.4.3; our App
  Review notes promise no leaderboards and that BAC is never compared): no max
  BAC, no "most drinks in a night", no streaks, no rankings, no comparisons.
- Publishing anything about incognito nights.
- Making the app slower: stats publishing never blocks the UI.

## Decisions

### Speed

- **Optimistic UI.** Send / accept / decline / cancel change the row at once
  (e.g. "Friends ✓", "Requested"); the callable runs in the background; on
  failure the row goes back and the existing error alert shows.
- **No forced token refresh.** `callFunction`'s default becomes
  `forcingTokenRefresh: false` (Firebase refreshes an expiring token itself).
  Callers that truly need fresh claims keep passing `true` explicitly
  (account deletion already passes its own `idToken`). Audit every caller.
- **Lazy-load heavy server modules.** In `functions/index.js`, modules only a
  few functions use — `@google-cloud/vision`, `@anthropic-ai/sdk`,
  report/recovery/prompt code, `./recovery/image` (pulls `@google/genai` and
  `sharp`), `./purchases` (App Store server library), `./drink-lookup` — are
  required inside the functions that use them (memoized), so a cold start of a
  social callable doesn't load them. Behavior is unchanged.

### Display name

- New optional field `name` on `public_profiles/{uid}`: trimmed, 1–30
  characters, letters/numbers/spaces and common punctuation; no control
  characters; run through the existing username moderation word list. Empty
  clears it.
- Set through a new callable `setDisplayName({name})` (clients can't write
  `public_profiles`). App Check enforced, like the other social callables.
- Edited in Social profile ("Name" field under the photo). If empty, the app
  shows only the @username, as today.
- Visible to anyone who can see the profile card (like the username). Shown on
  the friend profile, in My Friends rows and in search results (name above
  @username when set).

### Stats (option 1: computed on the phone)

- Collection `profile_stats/{uid}`, one doc per user, written by the owner's
  app:
  - `nights` — nights logged, all time, excluding incognito nights and nights
    with no drinks;
  - `avg_drinks` — average logged drinks (servings) per night over the last
    90 days, same exclusions, one decimal;
  - `avg_water` — average waters logged per night, same window;
  - `favorite_drink` — the drink type logged most in the last 90 days (name,
    max 40 chars), or absent;
  - `member_since` — the account creation date (ms);
  - `updated_at` — ms.
- Rules: the owner may write their own doc with exactly these keys and sane
  ranges (counts 0…100 000, averages 0…100, strings capped); read allowed to
  the owner and to people in `friendships/{uid}/friends/{reader}`. Blocking
  already removes the friendship, so blocked people lose access.
- Published when a night ends, when incognito changes, on sign-in, and on
  foreground if the doc is older than 24 h — in the background, never blocking.
  Only written when a value changed.
- A "Show my stats to friends" switch in Social profile (on by default); off
  deletes the doc and stops publishing.
- Account deletion deletes `profile_stats/{uid}`.
- Friends on builds without this feature have no doc: the card shows
  "No stats yet".

### Friend profile screen

- New screen pushed from a friend's avatar/name in the feed and from My
  Friends rows: big photo (or the colored initial), name, @username, the stats
  card, then the existing night section (live / last 24 h) and the existing
  report/block menu.
- Reads `public_profiles/{uid}` and `profile_stats/{uid}` (one-time read when
  opened, refreshed on pull).

## Left to the builder

Exact layout, animation and copy polish within the sketch below; how the app
detects "a value changed"; where the publish is triggered from in AppState;
the moderation reuse details.

```
┌──────────────────────────────┐
│      [  BIG PHOTO  ]         │
│      Lorenzo Orozco          │
│      @lalo                   │
│  ┌────────────────────────┐  │
│  │ 🌙 42  nights logged    │  │
│  │ 🍺 3.4 drinks / night   │  │  last 90 days
│  │ 💧 2.1 waters / night   │  │
│  │ ⭐ Favorite: Tequila    │  │
│  │ 📅 On TrackSip since May 2026 │
│  └────────────────────────┘  │
│  Tonight / last 24 h (as now)│
└──────────────────────────────┘
```
