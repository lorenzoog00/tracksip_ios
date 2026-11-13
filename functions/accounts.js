const {HttpsError} = require("firebase-functions/v2/https");

// eslint-disable-next-line require-jsdoc
async function deleteAccount({
  db,
  auth,
  bucket,
  uid,
  authTime,
  now = Date.now(),
}) {
  if (
    !Number.isFinite(authTime) ||
    now / 1000 - authTime > 300 ||
    authTime > now / 1000 + 60
  ) {
    throw new HttpsError(
        "unauthenticated",
        "Please sign in again before deleting your account.",
    );
  }
  // Block writes and late reports while old ID tokens remain valid.
  await db.doc(`account_deletions/${uid}`).set({startedAt: now});
  await db.recursiveDelete(db.doc(`users/${uid}`));
  await db.doc(`live_activities/${uid}`).delete();
  const owners = await db
      .collection("purchase_owners")
      .where("uid", "==", uid)
      .get();
  for (const owner of owners.docs) await owner.ref.delete();
  await deleteSocialData({db, bucket, uid});
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  return {deleted: true};
}

// Friends data: profile, handle, graph (both directions), requests, blocks
// (both directions), shared night, push token and avatar file.
// eslint-disable-next-line require-jsdoc
async function deleteSocialData({db, bucket, uid}) {
  // Found by owner, not via the profile: a retry after a partial failure has
  // no profile left to name the handle. Only handles owned by uid match.
  const handles = await db
      .collection("usernames")
      .where("uid", "==", uid)
      .get();
  for (const handle of handles.docs) await handle.ref.delete();

  const friends = await db.collection(`friendships/${uid}/friends`).get();
  for (const friend of friends.docs) {
    await db.doc(`friendships/${friend.id}/friends/${uid}`).delete();
  }
  await db.recursiveDelete(db.doc(`friendships/${uid}`));

  for (const field of ["from", "to"]) {
    const requests = await db
        .collection("friend_requests")
        .where(field, "==", uid)
        .get();
    for (const request of requests.docs) await request.ref.delete();
  }

  await db.recursiveDelete(db.doc(`blocks/${uid}`));
  const blockedBy = await db
      .collectionGroup("blocked")
      .where("uid", "==", uid)
      .get();
  for (const block of blockedBy.docs) await block.ref.delete();

  await db.doc(`shared_nights/${uid}`).delete();
  await db.doc(`push_tokens/${uid}`).delete();
  await bucket.file(`avatars/${uid}.jpg`).delete({ignoreNotFound: true});
  // Last, so a failed earlier step leaves the profile for the retry.
  await db.doc(`public_profiles/${uid}`).delete();
}

module.exports = {deleteAccount};
