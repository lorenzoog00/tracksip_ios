const {HttpsError} = require("firebase-functions/v2/https");

// eslint-disable-next-line require-jsdoc
async function deleteAccount({db, auth, uid, authTime, now = Date.now()}) {
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
  const owners = await db
      .collection("purchase_owners")
      .where("uid", "==", uid)
      .get();
  for (const owner of owners.docs) await owner.ref.delete();
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  return {deleted: true};
}

module.exports = {deleteAccount};
