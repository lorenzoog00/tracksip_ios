const {HttpsError} = require("firebase-functions/v2/https");
const {assertNotDeleting} = require("./social");

// ---------------------------------------------------------------------------
// Night reactions and comments
// ---------------------------------------------------------------------------

const REACTIONS = {
  beer: "🍻",
  fire: "🔥",
  laugh: "😂",
  woozy: "🥴",
  water: "💧",
  heart: "❤️",
};
const REACTION_PUSH_GAP_MS = 15 * 60 * 1000;
const MAX_TRACKED_UIDS = 50;

/**
 * The id of a night's thread: the owner and the night's start in ms.
 * Firebase uids contain no underscore, so the key splits unambiguously.
 * @param {string} owner the night owner's uid
 * @param {number} startedAt the shared night's start in ms
 * @return {string} the thread key
 */
function nightKey(owner, startedAt) {
  return `${owner}_${startedAt}`;
}

/**
 * Loads the shared night a caller wants to interact with and checks they may.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.owner the night owner's uid
 * @param {number} params.startedAt the night's start in ms
 * @param {string} params.uid the caller
 * @param {number} params.now current time in ms
 * @return {Promise<{night: object, ownerName: string, viewerName: string}>}
 *     the shared night data and both usernames
 */
async function loadNight({db, owner, startedAt, uid, now}) {
  const nightDoc = await db.doc(`shared_nights/${owner}`).get();
  const night = nightDoc.exists ? nightDoc.data() : null;
  const expiresAt = night && night.expires_at && night.expires_at.toMillis();
  if (!night || night.started_at !== startedAt || !(expiresAt > now)) {
    throw new HttpsError("not-found", "This night is no longer available.");
  }

  if (uid !== owner) {
    const [friend, blockedOwner, blockedViewer] = await Promise.all([
      db.doc(`friendships/${owner}/friends/${uid}`).get(),
      db.doc(`blocks/${uid}/blocked/${owner}`).get(),
      db.doc(`blocks/${owner}/blocked/${uid}`).get(),
    ]);
    if (!friend.exists || blockedOwner.exists || blockedViewer.exists) {
      throw new HttpsError("permission-denied", "You can't see this night.");
    }
  }

  const [viewerProfile, ownerProfile] = await Promise.all([
    db.doc(`public_profiles/${uid}`).get(),
    db.doc(`public_profiles/${owner}`).get(),
  ]);
  if (!viewerProfile.exists) {
    throw new HttpsError("failed-precondition", "Pick a username first.");
  }
  return {
    night,
    ownerName: ownerProfile.exists ? ownerProfile.data().username : "",
    viewerName: viewerProfile.data().username,
  };
}

/**
 * Keeps the newest entries of a list, dropping the oldest.
 * @param {string[]} list uids, newest last
 * @return {string[]} at most MAX_TRACKED_UIDS entries
 */
function capped(list) {
  return list.slice(-MAX_TRACKED_UIDS);
}

/**
 * Sends the owner a reaction push, swallowing failures: the reaction is
 * already committed and is the source of truth.
 * @param {Function} notify injected notifier
 * @param {string} toUid recipient
 * @param {object} payload the push payload
 */
async function notifyReactionSafely(notify, toUid, payload) {
  try {
    await notify(toUid, "reaction", payload);
  } catch (error) {
    console.error("notify reaction failed", error);
  }
}

/**
 * Sets, changes or removes the caller's single reaction on a friend's night.
 * Tapping the reaction already held removes it; null removes it too.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{owner: string, startedAt: number, emoji: ?string}} params.data
 *     the request payload; emoji is a REACTIONS key or null
 * @param {Function} params.notify (toUid, kind, payload) => Promise
 * @param {number} [params.now] current time in ms
 * @return {Promise<{emoji: ?string}>} the caller's reaction afterwards
 */
async function reactToNight({db, uid, data, notify, now = Date.now()}) {
  const {owner, startedAt, emoji} = data || {};
  if (typeof owner !== "string" || owner === "" || owner.includes("/") ||
      !Number.isFinite(startedAt)) {
    throw new HttpsError("invalid-argument", "That night isn't valid.");
  }
  if (emoji != null && !Object.hasOwn(REACTIONS, emoji)) {
    throw new HttpsError("invalid-argument", "That reaction isn't allowed.");
  }
  if (uid === owner) {
    throw new HttpsError("permission-denied",
        "You can't react to your own night.");
  }
  const {night, ownerName, viewerName} =
      await loadNight({db, owner, startedAt, uid, now});

  const threadRef = db.doc(`night_threads/${nightKey(owner, startedAt)}`);
  const reactionRef = threadRef.collection("reactions").doc(uid);
  const outcome = await db.runTransaction(async (tx) => {
    const [deleting, thread, existing] = await Promise.all([
      tx.get(db.doc(`account_deletions/${uid}`)),
      tx.get(threadRef),
      tx.get(reactionRef),
    ]);
    assertNotDeleting(deleting);

    const previous = existing.exists ? existing.data().emoji : null;
    const next = emoji == null || emoji === previous ? null : emoji;
    const summary = thread.exists ? thread.data() : {};
    const counts = {...(summary.reactions || {})};
    if (previous) counts[previous] = Math.max(0, (counts[previous] || 0) - 1);
    if (next) counts[next] = (counts[next] || 0) + 1;

    let reactors = (summary.reactors || []).filter((id) => id !== uid);
    if (next) reactors = capped([...reactors, uid]);

    const pushed = summary.pushed_reactors || [];
    const lastPush = summary.last_reaction_push_at;
    const mayPush = next !== null && !pushed.includes(uid) &&
        (typeof lastPush !== "number" || now - lastPush >= REACTION_PUSH_GAP_MS);
    let sinceLast = summary.reactions_since_push || 0;
    const update = {};
    let others = null;
    if (mayPush) {
      others = sinceLast;
      sinceLast = 0;
      update.last_reaction_push_at = now;
      update.pushed_reactors = capped([...pushed, uid]);
    } else if (next !== null && !previous && !pushed.includes(uid)) {
      sinceLast += 1;
    }

    tx.set(threadRef, {
      owner,
      started_at: startedAt,
      expires_at: night.expires_at,
      reactions: counts,
      reactors,
      reactions_since_push: sinceLast,
      comment_count: summary.comment_count || 0,
      latest_comments: summary.latest_comments || [],
      ...update,
    }, {merge: true});
    if (next) {
      tx.set(reactionRef, {
        uid,
        username: viewerName,
        emoji: next,
        at: now,
        expires_at: night.expires_at,
      });
    } else {
      tx.delete(reactionRef);
    }
    return {emoji: next, others};
  });

  if (outcome.others !== null) {
    await notifyReactionSafely(notify, owner, {
      from: viewerName,
      owner,
      ownerName,
      startedAt,
      emoji: REACTIONS[outcome.emoji],
      others: outcome.others,
    });
  }
  return {emoji: outcome.emoji};
}

module.exports = {REACTIONS, nightKey, loadNight, reactToNight};
