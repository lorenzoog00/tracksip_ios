const {tokenIsDead} = require("./live-activity");
const {nightKey} = require("./interactions");

// Friends hear when someone starts a night they can see. shared_nights/{uid}
// exists only for such nights: an incognito night never writes it, so it
// never notifies anyone. Every drink rewrites the doc, so isNewNight lets
// through only the write that brings a new, still-open, recent night.

// At most one push per sender in this window: starting, ending and starting
// again, or moving a night's start, never pushes twice.
const COOLDOWN_MS = 12 * 3600000;
// A night that began longer ago than this (logged late, or made visible long
// after it started) notifies nobody.
const FRESH_MS = 6 * 3600000;
// Refs per getAll: each friend costs two (token and prefs).
const FRIENDS_PER_READ = 100;

/**
 * The started_at to tell friends about, or null when this write is not a new
 * night: the doc is gone, the night has ended, started_at is unchanged (one
 * more drink on the same night) or the night began over FRESH_MS ago.
 * @param {object|undefined} before the doc's data before the write
 * @param {object|undefined} after the doc's data after the write
 * @param {number} now current time in ms
 * @return {?number} the night's started_at in ms, or null
 */
function isNewNight(before, after, now) {
  if (!after) return null;
  const startedAt = after.started_at;
  if (!Number.isFinite(startedAt)) return null;
  if (after.ended_at != null) return null;
  if (before && before.started_at === startedAt) return null;
  if (now - startedAt > FRESH_MS) return null;
  return startedAt;
}

/**
 * Whether a friend's app takes this push: it has a token, registered the
 * "nights" feature (an app too old to switch these off never did) and has
 * not set friend_nights to false.
 * @param {object} token the push_tokens snapshot
 * @param {object} prefs the notification_prefs snapshot
 * @return {boolean}
 */
function wantsNightPush(token, prefs) {
  if (!token.exists) return false;
  const {features} = token.data();
  if (!Array.isArray(features) || !features.includes("nights")) return false;
  return !(prefs.exists && prefs.data().friend_nights === false);
}

/**
 * Pushes "@username started a night" to every friend of the owner who can
 * see it. night_start_pushes/{uid} is checked and written in one transaction
 * before anything is sent, so a retried or duplicated trigger, the same night
 * shown again, or a second night inside COOLDOWN_MS sends nothing: at most
 * one push, never two. Dead tokens are deleted.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the night's owner
 * @param {number} params.startedAt the night's started_at in ms
 * @param {Function} params.send (environment, token, payload) =>
 *     {status, reason}
 * @param {number} [params.now] current time in ms
 * @return {Promise<{sent: number, skipped: ?string}>} skipped names why
 *     nothing went out: "deleting", "no-profile", "duplicate" or "cooldown"
 */
async function notifyFriendsOfNight({
  db, uid, startedAt, send, now = Date.now(),
}) {
  const [profile, deleting] = await Promise.all([
    db.doc(`public_profiles/${uid}`).get(),
    db.doc(`account_deletions/${uid}`).get(),
  ]);
  if (deleting.exists) return {sent: 0, skipped: "deleting"};
  if (!profile.exists) return {sent: 0, skipped: "no-profile"};

  const markRef = db.doc(`night_start_pushes/${uid}`);
  const skipped = await db.runTransaction(async (tx) => {
    const mark = await tx.get(markRef);
    if (mark.exists) {
      const last = mark.data();
      if (last.started_at === startedAt) return "duplicate";
      if (now - last.sent_at < COOLDOWN_MS) return "cooldown";
    }
    tx.set(markRef, {started_at: startedAt, sent_at: now});
    return null;
  });
  if (skipped) return {sent: 0, skipped};

  const payload = {
    aps: {
      "alert": {body: `@${profile.data().username} started a night`},
      "sound": "default",
      // Grouped with that night's reaction and comment pushes.
      "thread-id": nightKey(uid, startedAt),
    },
    // The same night sheet a reaction push opens.
    route: "thread",
    owner: uid,
    started_at: startedAt,
  };
  const friends = await db.collection(`friendships/${uid}/friends`).get();
  const ids = friends.docs.map((doc) => doc.id);
  let sent = 0;
  for (let i = 0; i < ids.length; i += FRIENDS_PER_READ) {
    const chunk = ids.slice(i, i + FRIENDS_PER_READ);
    const snaps = await db.getAll(...chunk.flatMap((id) => [
      db.doc(`push_tokens/${id}`),
      db.doc(`notification_prefs/${id}`),
    ]));
    await Promise.all(chunk.map(async (id, index) => {
      const token = snaps[2 * index];
      if (!wantsNightPush(token, snaps[2 * index + 1])) return;
      const {token: deviceToken, environment} = token.data();
      const result = await send(environment, deviceToken, payload);
      if (tokenIsDead(result)) {
        await token.ref.delete();
      } else if (result.status === 200) {
        sent++;
      }
    }));
  }
  return {sent, skipped: null};
}

module.exports = {
  COOLDOWN_MS, FRESH_MS, isNewNight, notifyFriendsOfNight,
};
