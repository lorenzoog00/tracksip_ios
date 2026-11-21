const crypto = require("node:crypto");
const {avatarUrl} = require("../avatar");

// Each photo lives at its own path with its own download token, and a new
// photo always gets a new path or token, so a cached copy can never go stale.
const PHOTO_CACHE_CONTROL = "public, max-age=31536000, immutable";

const PHOTO_STYLE = "Overhead shot at about 45 degrees on a dark stone " +
  "table, warm morning window light, shallow depth of field. No people or " +
  "faces, no text, no logos or brands.";

const NOT_FOUND = 5;
// The library item is created a moment before the plan doc is written.
const PLAN_RETRY_MS = 5000;

/**
 * The text prompt for one library item.
 * @param {{name: string, kind: string}} item
 * @return {string}
 */
function photoPrompt({name, kind}) {
  return kind === "activity" ?
    `${PHOTO_STYLE} A scene or objects that show: ${name}. No people.` :
    `${PHOTO_STYLE} Subject: ${name}.`;
}

/**
 * Generates one photo: 4:3 at the 1K size, resized to an 800 px wide JPEG.
 * @param {{name: string, kind: string}} item
 * @param {{genai: object, model: string}} deps A GoogleGenAI client.
 * @return {Promise<Buffer>}
 */
async function generatePhoto(item, {genai, model}) {
  const response = await genai.models.generateContent({
    model,
    contents: photoPrompt(item),
    config: {
      responseModalities: ["IMAGE"],
      imageConfig: {aspectRatio: "4:3", imageSize: "1K"},
    },
  });
  const parts = response.candidates?.[0]?.content?.parts ?? [];
  const image = parts.find((part) => part.inlineData?.data);
  if (!image) throw new Error("The image model returned no image.");
  // Loaded here, not at the top: index.js requires this file, and sharp's
  // native module would otherwise load on every function's cold start.
  const sharp = require("sharp");
  return sharp(Buffer.from(image.inlineData.data, "base64"))
      .resize({width: 800})
      .jpeg({quality: 80})
      .toBuffer();
}

/**
 * The plan with one item's photo set, matched by `itemId`.
 * @param {object} plan The stored `plan` map.
 * @param {string} itemId
 * @param {string} photoUrl
 * @return {object} A new plan; the input is untouched.
 */
function withPhoto(plan, itemId, photoUrl) {
  const set = (entry) =>
    entry && entry.itemId === itemId ? {...entry, photoUrl} : entry;
  return {
    ...plan,
    breakfast: set(plan.breakfast),
    activities: (plan.activities ?? []).map(set),
  };
}

/**
 * One try at filling a plan's photo. The read and the write share a
 * transaction, so two photos for one plan cannot overwrite each other, and
 * only ever `update`s, so a plan doc deleted with its account is never
 * recreated.
 * @param {object} db Firestore
 * @param {string} path The plan doc path.
 * @param {string} itemId
 * @param {string} photoUrl
 * @return {Promise<boolean>} False when the plan doc is not there.
 */
async function tryFillPlan(db, path, itemId, photoUrl) {
  const ref = db.doc(path);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;
      const plan = snap.data().plan;
      if (plan) tx.update(ref, {plan: withPhoto(plan, itemId, photoUrl)});
      return true;
    });
  } catch (error) {
    if (error.code === NOT_FOUND) return false;
    throw error;
  }
}

/**
 * Fills a photo into one waiting plan. A missing doc is retried once after a
 * short wait, then dropped silently.
 * @param {object} args `{db, path, itemId, photoUrl, wait}`.
 * @return {Promise<void>}
 */
async function fillPlan({db, path, itemId, photoUrl, wait}) {
  try {
    if (await tryFillPlan(db, path, itemId, photoUrl)) return;
    await wait(PLAN_RETRY_MS);
    await tryFillPlan(db, path, itemId, photoUrl);
  } catch (error) {
    console.error("recovery photo: plan update failed", path, error);
  }
}

/**
 * Removes the processed paths from the item's pending list, keeping any a
 * plan added in the meantime.
 * @param {object} db Firestore
 * @param {object} ref The library item.
 * @param {Set<string>} done
 * @return {Promise<void>}
 */
function clearPaths(db, ref, done) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const left = (snap.data().pendingPlanPaths ?? [])
        .filter((path) => !done.has(path));
    tx.update(ref, {pendingPlanPaths: left});
  });
}

/**
 * Generates the photo of a `generating` library item, stores it, and fills it
 * into the plans waiting on it. Never throws for a failed photo: the item is
 * marked `failed` and the plans keep their icon tile.
 * @param {object} args
 * @param {object} args.db Firestore
 * @param {{name: string, file: Function}} args.bucket Cloud Storage bucket
 * @param {string} args.itemId
 * @param {Function} args.generate ({name, kind}) => Promise<Buffer>
 * @param {number|Date} args.now
 * @param {boolean} [args.versioned] Write to a new path so photo URLs
 *   already copied into plans keep working (used by regeneration).
 * @param {Function} [args.wait] (ms) => Promise, for tests.
 * @return {Promise<void>}
 */
async function completeLibraryPhoto({
  db, bucket, itemId, generate, now, versioned = false,
  wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
}) {
  const ref = db.doc(`recovery_library/${itemId}`);
  const snap = await ref.get();
  if (!snap.exists) return;
  const item = snap.data();
  // A retried event must not pay for a second photo.
  if (item.photoStatus !== "generating") return;
  const paths = item.pendingPlanPaths ?? [];

  let photoUrl;
  let photoPath;
  try {
    const buffer = await generate({name: item.name, kind: item.kind});
    photoPath = versioned ?
      `recovery-library/${itemId}-${Number(now)}.jpg` :
      `recovery-library/${itemId}.jpg`;
    const token = crypto.randomUUID();
    await bucket.file(photoPath).save(buffer, {
      // Custom metadata only counts under metadata.metadata, as for avatars.
      metadata: {
        contentType: "image/jpeg",
        cacheControl: PHOTO_CACHE_CONTROL,
        metadata: {firebaseStorageDownloadTokens: token},
      },
    });
    photoUrl = avatarUrl({
      bucket: bucket.name, path: photoPath, token, nowMs: Number(now),
    });
  } catch (error) {
    console.error("recovery photo failed", itemId, error);
    await ref.update({photoStatus: "failed"});
    await clearPaths(db, ref, new Set(paths));
    return;
  }

  await ref.update({photoStatus: "ready", photoUrl, photoPath});
  // Plans can register on this item while the image is being made, so the
  // list is re-read until nothing new is waiting.
  const done = new Set();
  let waiting = paths;
  while (waiting.length > 0) {
    await Promise.all(waiting.map((path) =>
      fillPlan({db, path, itemId, photoUrl, wait})));
    waiting.forEach((path) => done.add(path));
    const fresh = (await ref.get()).data().pendingPlanPaths ?? [];
    waiting = fresh.filter((path) => !done.has(path));
  }
  await clearPaths(db, ref, done);
}

module.exports = {
  PHOTO_STYLE,
  PHOTO_CACHE_CONTROL,
  photoPrompt,
  generatePhoto,
  completeLibraryPhoto,
  withPhoto,
};
