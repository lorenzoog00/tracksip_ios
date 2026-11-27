# Push when a friend starts a night — design

Approved by the owner on 2026-11-27 ("Sí, adelante") after the four decisions below were proposed.

## Intent

When one of your friends starts a night, you get a push. The owner asked for it in Spanish: "push notification cuando uno de tus amigos empieza una noche".

## Decisions (owner-approved)

1. **Who gets it:** every friend of the person who started the night. Per-friend muting is out of scope for now.
2. **Turning it off:**
   - Receiver: a new switch, "Friends starting a night", in Social profile → Notifications (`notification_prefs.friend_nights`). A missing key means on, like the other switches.
   - Sender: nothing new. An incognito night never writes `shared_nights/{uid}`, so it never notifies anyone.
3. **Several nights in a row:** at most one push per sender every 12 h. Also covers editing a night's start time and closing and reopening nights. A night that started more than 6 h ago never notifies (a night logged late, or one made visible long after it started).
4. **Copy:** "@alex started a night". It uses the same format as the other pushes and stays neutral for App Store 1.4.3. A tap opens that night over the feed, which is the screen a reaction push already opens (route `thread`).

Only apps that ship the switch get these pushes: the app registers a new push feature, `"nights"`. This is the same gate reactions and comments use with `"threads"`.

## Approaches (my call; the owner talks outcomes)

- **Trigger on `shared_nights/{uid}` writes (chosen).** This doc exists only for nights friends can see: not incognito, and the person has a username. It is also exactly what a friend sees when they tap. It fires on every rewrite (each drink), so the function returns early unless `started_at` is new.
- **Trigger on `users/{uid}/night_events` create.** It fires once per night, but it also fires for incognito nights and for people with no username. Turning incognito off later would never notify. Rejected.
- **The app calls a callable when a night starts.** This adds a client round-trip and can be forged or skipped offline. Rejected.

## How it works

- **Trigger:** `notifyFriendsOfNight`, an `onDocumentWritten("shared_nights/{uid}")` function with the APNs secret. It acts only when all of these hold:
  - the doc exists after the write;
  - it has no `ended_at`;
  - `started_at` differs from the doc before the write, or there was no doc before;
  - `started_at` is at most 6 h old.
- **Dedupe and cooldown:** a transaction on `night_start_pushes/{uid}` stores `{started_at, sent_at}`. If the stored `started_at` matches, or `sent_at` is under 12 h old, nothing is sent. This also makes a retried event harmless. The doc is written before sending, so a push is sent at most once.
- **Who is skipped:** the sender if they have no `public_profiles` doc or their account deletion has started.
- **Recipients:** the ids in `friendships/{uid}/friends`. These are the people the rules let read the night, and blocking removes them. For each recipient, `push_tokens` and `notification_prefs` are batch-read. A recipient gets the push only if they have a token, the token's features include `"nights"`, and `friend_nights` is not `false`. Dead tokens are deleted.
- **Payload:** `aps.alert.body` = `@username started a night`, `sound` = default, and `thread-id` = the night key, so it groups with that night's reactions. It also carries `route: "thread"`, `owner` and `started_at`.
- **Backend changes elsewhere:**
  - `PUSH_FEATURES` gains `"nights"`.
  - The rules let `notification_prefs` hold `friend_nights` (bool).
  - Account deletion deletes `night_start_pushes/{uid}`.
- **iOS:**
  - `pushFeatures` gains `"nights"`.
  - A `NotificationPrefs` value parses the prefs doc, with each key defaulting to on.
  - The new toggle in `SocialProfileView`.
  - No routing change, because `thread` is already handled.

## Tests

- **Unit (`night-start.test.js`):** which writes count as a new night.
- **Emulator:**
  - the fan-out;
  - prefs off, a missing feature, no token and dead tokens;
  - the cooldown and the same-`started_at` dedupe;
  - no username, and an account deletion in progress;
  - the `friend_nights` rules;
  - account deletion removing the cooldown doc.
- **Swift Testing:** `NotificationPrefs` defaults and parsing, and `pushFeatures` including `"nights"`.

## Non-goals

- Per-friend mute.
- Batching several friends into one push.
- A push when a night ends.
- Any copy that invites joining.
