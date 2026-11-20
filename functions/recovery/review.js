const {HttpsError} = require("firebase-functions/v2/https");

const MAX_PENDING = 50;
const ACTIONS = new Set(["approve", "reject", "regenerate"]);

/**
 * Whether a uid is an app admin. Same list format as `isProTester`.
 * @param {string|undefined} uid
 * @param {string} raw Comma or whitespace separated uids.
 * @return {boolean}
 */
function isAdmin(uid, raw) {
  if (!uid || typeof raw !== "string") return false;
  return raw
      .split(/[\s,]+/)
      .some((entry) => entry.length > 0 && entry === uid);
}

/**
 * Throws unless the caller is a signed-in admin.
 * @param {{uid: string}|undefined} auth The callable's `request.auth`.
 * @param {string} raw The ADMIN_UIDS value.
 */
function requireAdmin(auth, raw) {
  if (!auth) throw new HttpsError("unauthenticated", "Please sign in.");
  if (!isAdmin(auth.uid, raw)) {
    throw new HttpsError("permission-denied", "Admins only.");
  }
}

/**
 * Milliseconds of a stored `createdAt` (number, Date or Timestamp).
 * @param {*} value
 * @return {number}
 */
function millis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  return Number(value) || 0;
}

/**
 * Library items whose photo awaits review, newest first, at most 50. Queries
 * on `review` alone and sorts here, so no composite index is needed.
 * @param {{db: object}} args
 * @return {Promise<{items: object[]}>}
 */
async function listPendingPhotos({db}) {
  const snap = await db.collection("recovery_library")
      .where("review", "==", "pending").get();
  const items = snap.docs
      .map((doc) => ({id: doc.id, ...doc.data()}))
      .sort((a, b) => millis(b.createdAt) - millis(a.createdAt))
      .slice(0, MAX_PENDING)
      .map(({id, name, kind, countries, photoUrl, photoStatus}) =>
        ({id, name, kind, countries, photoUrl, photoStatus}));
  return {items};
}

/**
 * Approves, rejects or regenerates one library photo.
 * @param {object} args
 * @param {object} args.db Firestore
 * @param {string} args.itemId
 * @param {string} args.action "approve" | "reject" | "regenerate"
 * @param {Function} [args.regenerate] (itemId) => Promise, runs generation.
 * @return {Promise<object>} `{ok: true}`; regenerate also returns the final
 *   `photoStatus` and `photoUrl`. A failed photo is reported, not thrown.
 */
async function reviewPhoto({db, itemId, action, regenerate}) {
  if (typeof itemId !== "string" || itemId.length === 0 ||
      itemId.includes("/")) {
    throw new HttpsError("invalid-argument", "itemId is required.");
  }
  if (!ACTIONS.has(action)) {
    throw new HttpsError("invalid-argument", "Unknown action.");
  }
  const ref = db.doc(`recovery_library/${itemId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "No such item.");
  if (action === "approve") {
    await ref.update({review: "approved"});
  } else if (action === "reject") {
    await ref.update({review: "rejected"});
  } else {
    await ref.update({photoStatus: "generating"});
    await regenerate(itemId);
    const after = (await ref.get()).data();
    return {ok: true, photoStatus: after.photoStatus,
      photoUrl: after.photoUrl ?? null};
  }
  return {ok: true};
}

module.exports = {
  isAdmin,
  requireAdmin,
  listPendingPhotos,
  reviewPhoto,
  MAX_PENDING,
};
