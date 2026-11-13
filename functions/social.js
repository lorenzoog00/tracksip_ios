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

module.exports = {claimUsername, searchUsers};
