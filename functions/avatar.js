const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const {FieldValue} = require("firebase-admin/firestore");

const MAX_BYTES = 512 * 1024;
const MAX_BASE64_LENGTH = Math.ceil(MAX_BYTES / 3) * 4;
const REJECTED = "That photo can't be used.";

/**
 * The public download URL for a stored avatar. Pure so it can be tested.
 * @param {{bucket: string, path: string, token: string, nowMs: number}} o
 * @return {string}
 */
function avatarUrl({bucket, path, token, nowMs}) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${token}&v=${nowMs}`;
}

/**
 * Decodes and sanity-checks the uploaded JPEG.
 * @param {*} value the base64 payload
 * @return {Buffer}
 */
function decodeJpeg(value) {
  if (typeof value !== "string" || value === "") {
    throw new HttpsError("invalid-argument", "Missing photo.");
  }
  if (value.length > MAX_BASE64_LENGTH) {
    throw new HttpsError("invalid-argument", "That photo is too large.");
  }
  const buffer = Buffer.from(value, "base64");
  if (buffer.length > MAX_BYTES) {
    throw new HttpsError("invalid-argument", "That photo is too large.");
  }
  const isJpeg = buffer.length > 3 &&
    buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  if (!isJpeg) throw new HttpsError("invalid-argument", REJECTED);
  return buffer;
}

/**
 * Whether a SafeSearch verdict is too risky for a public avatar.
 * @param {{adult: string, violence: string, racy: string}} verdict
 * @return {boolean}
 */
function isRejected({adult, violence, racy}) {
  const likely = ["LIKELY", "VERY_LIKELY"];
  return likely.includes(adult) ||
    likely.includes(violence) ||
    racy === "VERY_LIKELY";
}

/**
 * Sets or removes the caller's profile photo. Nothing is stored unless
 * SafeSearch passes; a SafeSearch outage fails closed.
 * @param {object} params
 * @param {object} params.db Firestore
 * @param {{name: string, file: Function}} params.bucket Cloud Storage bucket
 * @param {string} params.uid the caller
 * @param {{jpegBase64: ?string}} params.data the request payload
 * @param {Function} params.safeSearch (Buffer) => {adult, violence, racy}
 * @return {Promise<{photo_url: ?string}>}
 */
async function setAvatar({db, bucket, uid, data, safeSearch}) {
  const profileRef = db.doc(`public_profiles/${uid}`);
  const path = `avatars/${uid}.jpg`;
  const wantsRemoval = data && data.jpegBase64 === null;

  const buffer = wantsRemoval ? null : decodeJpeg(data && data.jpegBase64);
  if (!(await profileRef.get()).exists) {
    throw new HttpsError("failed-precondition", "Pick a username first.");
  }

  if (wantsRemoval) {
    await bucket.file(path).delete({ignoreNotFound: true});
    await profileRef.update({photo_url: FieldValue.delete()});
    return {photo_url: null};
  }

  let verdict;
  try {
    verdict = await safeSearch(buffer);
  } catch (error) {
    console.error("avatar safeSearch failed", error);
    throw new HttpsError(
        "unavailable", "Couldn't check that photo. Try again.");
  }
  if (isRejected(verdict)) throw new HttpsError("invalid-argument", REJECTED);

  const token = crypto.randomUUID();
  await bucket.file(path).save(buffer, {
    contentType: "image/jpeg",
    metadata: {firebaseStorageDownloadTokens: token},
  });
  const photoUrl = avatarUrl({
    bucket: bucket.name, path, token, nowMs: Date.now(),
  });
  await profileRef.update({photo_url: photoUrl});
  return {photo_url: photoUrl};
}

module.exports = {setAvatar, avatarUrl};
