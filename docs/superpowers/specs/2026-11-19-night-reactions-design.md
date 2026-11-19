# Night reactions, comments and mentions — design

Decided in a grilling session on 2026-11-19. Builds on Friends v1
(`2026-11-12-friends-design.md`) and on the friend-chart and contacts work in
PR #53. The aim: friends interact with each other's nights, BeReal style,
from the feed itself.

## Product decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Reactions | A fixed set of six: 🍻 🔥 😂 🥴 💧 ❤️. **One reaction per person per night.** Tapping another replaces it; tapping yours removes it. The owner cannot react to their own night |
| 2 | Feed card | Each shared night is a **post card**: avatar, @username, Live · duration (or "Ended 5h ago · 4h 30m"), BAC now (or peak), mini BAC curve (live: dashed projection), **drink summary** as chips grouped by drink ("Beer ×3", "Tequila ×2", water count), "Last: Tequila · 12 min ago", reaction bar with counts and your reaction highlighted, comment count, and the latest comment |
| 2b | Interaction from the feed | Tap an emoji on the card to react. Long-press (or the + button) fans out all six. Tap 💬 or the latest comment → **comment sheet**. Tap the rest of the card → the full night (Stats-style chart), which also shows reactions and comments |
| 2c | Comment sheet | Six reactions on top with yours marked, "Reacted: @beto, @lu, you", flat comment list, input with Send. Swipe down to close |
| 3 | Comment pushes | The owner gets every comment. Anyone who has commented on that night gets later comments by others. Reactions reach the owner only, grouped, at most one push per night every 15 min ("@beto and 2 others reacted to your night") |
| 4 | Comment rules | Text only, max 200 characters, no links or photos. Authors delete their own; the owner deletes any on their night. No editing. Long-press → Report (same reports pipeline). Blocks hide reactions and comments in both directions. Anyone who can see the night sees its comments. Everything expires with the night (24 h after close) |
| 5 | Your own night | Lives **only at the top of your feed**, same card, labelled "You", while live and for 24 h after. You can comment on it, not react. **A tapped push opens that night's comment sheet** directly, yours or a friend's |
| 6 | Notification switches | In your Social profile, three switches, all on by default: **Reactions on your night**, **Comments on your night**, **Replies and mentions**. No per-night mute. Friend requests and "@x is on TrackSip" stay as they are |
| 7 | Mentions | Typing `@` opens an animated suggestion list: the owner, people who reacted or commented, and your friends who are also the owner's friends. A picked name becomes a coloured pill. Only people who can see the night can be mentioned; any other `@name` stays plain text. Mentioned people get "@beto mentioned you on @ana's night" (under "Replies and mentions") |
| 8 | Fixed details | Flat comment list in arrival order. Every viewer sees who reacted. Ended nights take reactions and comments until they expire. Max 50 comments per person per night, one every 3 s. Changing a reaction notifies at most once per person per night. Unfriending keeps existing reactions and comments until the night expires, but the ex-friend can no longer see or add any. Older app versions see none of it |
| 9 | Motion | See "Motion" below. All of it honours Reduce Motion |

## Motion

Every interaction gets a haptic that matches its weight.

- **React**: the emoji springs up (scale 1 → 1.35 → 1), a short particle burst
  in the emoji's colour, the count rolls to the new number
  (`.contentTransition(.numericText())`). Changing reaction: the old one
  shrinks out while the new one springs in.
- **Picker**: long-press fans the six emojis out of the + button with a 30 ms
  stagger; the one under the finger grows; releasing on one reacts.
- **Card arrival**: the mini curve draws left to right (trim 0 → 1), drink
  chips cascade in, the Live dot breathes.
- **Comments**: the sheet rises on a spring; a sent comment appears at once
  from the bottom at 60 % opacity until the server confirms, then solidifies;
  the card's latest comment crossfades.
- **Mentions**: the suggestion list slides up above the keyboard; picked names
  become pills with a soft pop.
- **Reduce Motion**: springs become fades, no particles, no drawing.

## Data model (Firestore)

A night is identified by `nightKey = "{ownerUid}_{started_at}"`, `started_at`
being the shared night's start in ms. Firebase uids contain no `_`.

- `night_threads/{nightKey}` — summary, written only by functions:
  `{owner, started_at, expires_at, reactions: {beer: 3, fire: 1, …},
  reactors: [uid, …] (≤ 50, newest last), comment_count,
  latest_comments: [{id, uid, username, text, at}] (last 3),
  last_reaction_push_at}`. `expires_at` copies the shared night's, with the
  TTL policy, so threads vanish with the night.
- `night_threads/{nightKey}/reactions/{uid}` — `{uid, username, emoji, at,
  expires_at}`.
- `night_threads/{nightKey}/comments/{id}` — `{uid, username, text,
  mentions: [{uid, username}], at, expires_at}`.
- `notification_prefs/{uid}` — `{reactions, comments, replies}` booleans;
  missing means on. Owner read/write via rules with a key allowlist.

Reaction keys are words (`beer, fire, laugh, woozy, water, heart`), not emoji,
so a font change never breaks a stored value.

### Who can read

Rules allow `get` on `night_threads/{nightKey}` and `list`/`get` on its
subcollections to the owner (prefix of `nightKey`) and to their friends, while
`expires_at > request.time`. No client writes.

Blocks are filtered in two places: the server never accepts a reaction or
comment between two people where either blocked the other, and never pushes
across a block. The thread itself is read through the `getNightThread`
callable, which drops reactions and comments from anyone the reader blocked
or who blocked the reader. The feed card reads the summary doc directly and
hides latest comments from people the reader blocked. **Known limit**: a
latest-comment preview from someone who blocked *you* can still show on the
card (the client cannot know who blocked it); opening the thread never shows
it.

## Functions

All `onCall`, App Check enforced, thin shells over a new `interactions.js`.

- `reactToNight({owner, startedAt, emoji})` — `emoji: null` removes. Caller
  must be a friend of the owner, not the owner, no block either way, and the
  shared night must exist with that `started_at` and not be expired.
  Transaction updates the reaction doc and the summary counts. Pushes the
  owner (switch "reactions") if none went out for this night in the last
  15 min and this person has not triggered one before for this night.
- `addComment({owner, startedAt, text})` — caller is the owner or a friend;
  text trimmed, 1–200 chars, no URLs; rate limits (50 per person per night,
  3 s apart). Resolves `@names` to uids that can see the night and stores
  them. Pushes: owner gets "comment" (switch "comments") unless they wrote it;
  earlier commenters get "reply" (switch "replies"); mentioned people get
  "mention" (switch "replies") instead of "reply". Nobody gets two pushes for
  one comment.
- `deleteComment({owner, startedAt, commentId})` — author or owner.
- `getNightThread({owner, startedAt})` — reactions and comments, block-filtered,
  oldest first.
- `setNotificationPrefs` is not needed: the owner writes its own prefs doc.
- Trigger `onDocumentDeleted("shared_nights/{uid}")` deletes that owner's
  threads (going incognito, account deletion).
- Account deletion also removes the user's reactions and comments everywhere
  (collection-group queries on `uid`) and its prefs doc.

Push payloads carry `route: "thread"`, `owner`, `started_at`, so a tap opens
the sheet for that night.

## App

- `NightThreadStore` (per visible night): listens to `night_threads/{key}`,
  exposes counts, my reaction, latest comments; does optimistic react and
  comment with rollback on failure.
- `FeedPostCard` replaces `FeedRow`. `FeedView` puts your own night first
  ("You") when `shared_nights/{me}` is live or within 24 h.
- `NightThreadSheet`: reactions header, comments, mention-aware composer,
  report/delete via long-press. Polls `getNightThread` every 5 s while open
  and on push.
- `ReactionBar` + `ReactionPicker` with the motion above.
- Social profile gets a "Notifications" section with the three switches.
- `PushRoute.thread(owner:startedAt:)` opens the sheet over Social.

## Out of scope

Photo reactions (RealMoji), threaded replies, editing, per-night mute,
reactions on your own night, notifications for reaction changes beyond the
first, web.
