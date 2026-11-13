const {HttpsError} = require("firebase-functions/v2/https");
const {normalizeUsername, validateUsername} = require("./username-policy");

// ---------------------------------------------------------------------------
// Usernames and public profiles
// ---------------------------------------------------------------------------

const AVATAR_COLORS = [
  "#E8505B",
  "#F28C38",
  "#F2C14E",
  "#4CAF7A",
  "#2FA8A0",
  "#4A90D9",
  "#7A6FD6",
  "#C25BB0",
];
const SEARCH_LIMIT = 20;
const MIN_QUERY_LENGTH = 2;

/**
 * Picks a stable avatar color for a user.
 * @param {string} uid the user's id
 * @return {string} a color from the fixed palette
 */
function avatarColorFor(uid) {
  let hash = 0;
  for (const char of uid) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return AVATAR_COLORS[hash % AVATAR_COLORS.length];
}

/**
 * Claims a unique username for the caller, releasing their previous one.
 * The handle and public profile are written in a single transaction so two
 * users can never own the same name.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{username: string}} params.data the request payload
 * @return {Promise<{username: string}>} the stored (normalized) username
 */
async function claimUsername({db, uid, data}) {
  const raw = data && data.username;
  if (!validateUsername(raw).ok) {
    throw new HttpsError("invalid-argument", "That username isn't allowed.");
  }
  const username = normalizeUsername(raw);
  const handleRef = db.doc(`usernames/${username}`);
  const profileRef = db.doc(`public_profiles/${uid}`);

  await db.runTransaction(async (tx) => {
    const [handle, profile] = await Promise.all([
      tx.get(handleRef),
      tx.get(profileRef),
    ]);
    const current = profile.exists ? profile.data().username : null;
    if (handle.exists && handle.data().uid !== uid) {
      throw new HttpsError("already-exists", "That username is taken.");
    }
    if (current === username && handle.exists) return;

    if (current && current !== username) {
      tx.delete(db.doc(`usernames/${current}`));
    }
    tx.set(handleRef, {uid});
    if (profile.exists) {
      tx.update(profileRef, {username});
    } else {
      tx.set(profileRef, {username, avatar_color: avatarColorFor(uid)});
    }
  });
  return {username};
}

/**
 * Finds users whose username starts with the query.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{query: string}} params.data the request payload
 * @return {Promise<{results: object[]}>} matching public profiles, excluding
 *     the caller and anyone blocked in either direction
 */
async function searchUsers({db, uid, data}) {
  const query = normalizeUsername(data && data.query);
  if (query.length < MIN_QUERY_LENGTH) return {results: []};

  const blockedByCaller = new Set(
      (await db.collection(`blocks/${uid}/blocked`).get()).docs.map((d) => d.id),
  );
  // Over-fetch so exclusions rarely leave the page short.
  const snap = await db
      .collection("public_profiles")
      .orderBy("username")
      .startAt(query)
      .endAt(query + "")
      .limit(SEARCH_LIMIT * 3)
      .get();
  const candidates = snap.docs.filter(
      (d) => d.id !== uid && !blockedByCaller.has(d.id),
  );
  const blockedCaller = await Promise.all(
      candidates.map(
          async (d) => (await db.doc(`blocks/${d.id}/blocked/${uid}`).get()).exists,
      ),
  );
  const results = candidates
      .filter((_, i) => !blockedCaller[i])
      .slice(0, SEARCH_LIMIT)
      .map((d) => ({
        uid: d.id,
        username: d.data().username,
        photo_url: d.data().photo_url || null,
        avatar_color: d.data().avatar_color,
      }));
  return {results};
}

// ---------------------------------------------------------------------------
// Friend requests, friendships and blocks
// ---------------------------------------------------------------------------

/**
 * Validates a uid argument from the request payload.
 * @param {*} value the raw value
 * @param {string} caller the calling user's uid
 * @return {string} the uid
 */
function otherUid(value, caller) {
  if (typeof value !== "string" || value === "" || value.includes("/")) {
    throw new HttpsError("invalid-argument", "Missing user.");
  }
  if (value === caller) {
    throw new HttpsError("invalid-argument", "That's you.");
  }
  return value;
}

/**
 * Sends a notification without letting a failure leak out: the committed
 * friendship state is the source of truth.
 * @param {Function} notify injected notifier
 * @param {string} toUid recipient
 * @param {string} kind "request" or "accepted"
 * @param {string} fromUsername the acting user's username
 */
async function notifySafely(notify, toUid, kind, fromUsername) {
  try {
    await notify(toUid, kind, fromUsername);
  } catch (error) {
    console.error(`notify ${kind} failed`, error);
  }
}

/**
 * Sends a friend request, or accepts one the target already sent.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{toUid: string}} params.data the request payload
 * @param {Function} params.notify (toUid, kind, fromUsername) => Promise
 * @return {Promise<{status: string}>} "requested" or "friends"
 */
async function sendFriendRequest({db, uid, data, notify}) {
  const toUid = otherUid(data && data.toUid, uid);
  const now = Date.now();

  const outcome = await db.runTransaction(async (tx) => {
    const [me, them, blockedThem, blockedMe, friend, reverse, mine] =
      await Promise.all([
        tx.get(db.doc(`public_profiles/${uid}`)),
        tx.get(db.doc(`public_profiles/${toUid}`)),
        tx.get(db.doc(`blocks/${uid}/blocked/${toUid}`)),
        tx.get(db.doc(`blocks/${toUid}/blocked/${uid}`)),
        tx.get(db.doc(`friendships/${uid}/friends/${toUid}`)),
        tx.get(db.doc(`friend_requests/${toUid}_${uid}`)),
        tx.get(db.doc(`friend_requests/${uid}_${toUid}`)),
      ]);
    if (!me.exists) {
      throw new HttpsError("failed-precondition", "Pick a username first.");
    }
    if (!them.exists) {
      throw new HttpsError("not-found", "That user doesn't exist.");
    }
    if (blockedThem.exists || blockedMe.exists) {
      throw new HttpsError("permission-denied", "You can't add that user.");
    }
    const fromUsername = me.data().username;
    if (friend.exists) return {status: "friends"};
    if (reverse.exists) {
      tx.delete(reverse.ref);
      if (mine.exists) tx.delete(mine.ref);
      tx.set(db.doc(`friendships/${uid}/friends/${toUid}`), {since: now});
      tx.set(db.doc(`friendships/${toUid}/friends/${uid}`), {since: now});
      return {status: "friends", kind: "accepted", fromUsername};
    }
    if (mine.exists) return {status: "requested"};
    tx.set(mine.ref, {from: uid, to: toUid, created_at: now});
    return {status: "requested", kind: "request", fromUsername};
  });

  if (outcome.kind) {
    await notifySafely(notify, toUid, outcome.kind, outcome.fromUsername);
  }
  return {status: outcome.status};
}

/**
 * Accepts or declines a pending request addressed to the caller.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{fromUid: string, accept: boolean}} params.data the payload
 * @param {Function} params.notify (toUid, kind, fromUsername) => Promise
 * @return {Promise<{status: string}>} "friends" or "declined"
 */
async function respondToFriendRequest({db, uid, data, notify}) {
  const fromUid = otherUid(data && data.fromUid, uid);
  if (!data || typeof data.accept !== "boolean") {
    throw new HttpsError("invalid-argument", "Missing accept flag.");
  }
  const accept = data.accept;
  const now = Date.now();

  const outcome = await db.runTransaction(async (tx) => {
    const [request, me, blockedThem, blockedMe] = await Promise.all([
      tx.get(db.doc(`friend_requests/${fromUid}_${uid}`)),
      tx.get(db.doc(`public_profiles/${uid}`)),
      tx.get(db.doc(`blocks/${uid}/blocked/${fromUid}`)),
      tx.get(db.doc(`blocks/${fromUid}/blocked/${uid}`)),
    ]);
    if (!request.exists) {
      throw new HttpsError("not-found", "No such friend request.");
    }
    if (!accept) {
      tx.delete(request.ref);
      return {status: "declined"};
    }
    if (blockedThem.exists || blockedMe.exists) {
      throw new HttpsError("permission-denied", "You can't add that user.");
    }
    if (!me.exists) {
      throw new HttpsError("failed-precondition", "Pick a username first.");
    }
    tx.delete(request.ref);
    tx.set(db.doc(`friendships/${uid}/friends/${fromUid}`), {since: now});
    tx.set(db.doc(`friendships/${fromUid}/friends/${uid}`), {since: now});
    return {status: "friends", fromUsername: me.data().username};
  });

  if (outcome.status === "friends") {
    await notifySafely(notify, fromUid, "accepted", outcome.fromUsername);
  }
  return {status: outcome.status};
}

/**
 * Withdraws a request the caller sent.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{toUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "cancelled"
 */
async function cancelFriendRequest({db, uid, data}) {
  const toUid = otherUid(data && data.toUid, uid);
  await db.doc(`friend_requests/${uid}_${toUid}`).delete();
  return {status: "cancelled"};
}

/**
 * Ends a friendship on both sides.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{friendUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "removed"
 */
async function removeFriend({db, uid, data}) {
  const friendUid = otherUid(data && data.friendUid, uid);
  const batch = db.batch();
  batch.delete(db.doc(`friendships/${uid}/friends/${friendUid}`));
  batch.delete(db.doc(`friendships/${friendUid}/friends/${uid}`));
  await batch.commit();
  return {status: "removed"};
}

/**
 * Blocks a user and severs every tie with them in one atomic batch.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{targetUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "blocked"
 */
async function blockUser({db, uid, data}) {
  const targetUid = otherUid(data && data.targetUid, uid);
  const batch = db.batch();
  // The uid field lets account deletion find blocks via a collection group.
  batch.set(db.doc(`blocks/${uid}/blocked/${targetUid}`), {
    uid: targetUid,
    created_at: Date.now(),
  });
  batch.delete(db.doc(`friendships/${uid}/friends/${targetUid}`));
  batch.delete(db.doc(`friendships/${targetUid}/friends/${uid}`));
  batch.delete(db.doc(`friend_requests/${uid}_${targetUid}`));
  batch.delete(db.doc(`friend_requests/${targetUid}_${uid}`));
  await batch.commit();
  return {status: "blocked"};
}

/**
 * Lifts the caller's block on a user.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {string} params.uid the caller
 * @param {{targetUid: string}} params.data the request payload
 * @return {Promise<{status: string}>} always "unblocked"
 */
async function unblockUser({db, uid, data}) {
  const targetUid = otherUid(data && data.targetUid, uid);
  await db.doc(`blocks/${uid}/blocked/${targetUid}`).delete();
  return {status: "unblocked"};
}

module.exports = {
  claimUsername,
  searchUsers,
  sendFriendRequest,
  respondToFriendRequest,
  cancelFriendRequest,
  removeFriend,
  blockUser,
  unblockUser,
};
