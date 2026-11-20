#!/usr/bin/env node
//
// Uploads each reviewed photo to recovery-library/{id}.jpg in Cloud Storage
// and writes recovery_library/{id} (approved, ready). Writes to PRODUCTION, so
// it refuses without --confirm-production. --dry-run prints what it would
// write and touches nothing.
//
// Usage: node scripts/recovery-library/import-library.cjs --bucket <name>
//          --confirm-production [--dry-run] [--out <dir>]
// Uses Application Default Credentials.
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {
  DEFAULT_OUT_DIR, PROJECT_ID, requireFromFunctions, loadSeed, parseFlags,
} = require("./common.cjs");

/**
 * @param {string[]} argv
 * @return {{bucket: string, dryRun: boolean, only: ?string[], out: string}}
 */
function parseArgs(argv) {
  const flags = parseFlags(
      argv, ["confirm-production", "dry-run"], ["bucket", "only", "out"]);
  if (!flags["confirm-production"]) {
    throw new Error("Refusing to run: pass --confirm-production to write " +
      "to the production project.");
  }
  if (!flags.bucket) throw new Error("--bucket <name> is required");
  return {
    bucket: flags.bucket,
    dryRun: Boolean(flags["dry-run"]),
    only: flags.only === undefined ? null :
      flags.only.split(",").map((id) => id.trim()).filter(Boolean),
    out: flags.out ? path.resolve(flags.out) : DEFAULT_OUT_DIR,
  };
}

/**
 * Same URL shape as avatarUrl in functions/avatar.js.
 * @param {object} args `{bucket, storagePath, token, nowMs}`
 * @return {string}
 */
function tokenUrl({bucket, storagePath, token, nowMs}) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `${encodeURIComponent(storagePath)}?alt=media&token=${token}&v=${nowMs}`;
}

/**
 * The Firestore doc for one seed item.
 * @param {object} item A seed item.
 * @param {{bucket: string, token: string, now: number}} context
 * @return {object}
 */
function buildDoc(item, {bucket, token, now}) {
  const photoPath = `recovery-library/${item.id}.jpg`;
  return {
    ...item,
    review: "approved",
    photoStatus: "ready",
    photoUrl: tokenUrl({bucket, storagePath: photoPath, token, nowMs: now}),
    photoPath,
    createdAt: now,
    pendingPlanPaths: [],
  };
}

/**
 * Splits the seed into items with a photo file and ids without.
 * @param {object[]} seed
 * @param {string} dir
 * @param {Function} exists
 * @return {{ready: object[], missing: string[]}}
 */
function splitByPhoto(seed, dir, exists = fs.existsSync) {
  const ready = [];
  const missing = [];
  for (const item of seed) {
    if (exists(path.join(dir, `${item.id}.jpg`))) ready.push(item);
    else missing.push(item.id);
  }
  return {ready, missing};
}

/** @param {string[]} argv */
async function main(argv) {
  const args = parseArgs(argv);
  let seed = loadSeed();
  if (args.only) {
    const known = new Set(seed.map((item) => item.id));
    const unknown = args.only.filter((id) => !known.has(id));
    if (unknown.length > 0) {
      throw new Error(`Unknown ids in --only: ${unknown.join(", ")}`);
    }
    seed = seed.filter((item) => args.only.includes(item.id));
  }
  const {ready, missing} = splitByPhoto(seed, args.out);
  const now = Date.now();
  const docs = ready.map((item) => buildDoc(item, {
    bucket: args.bucket, token: crypto.randomUUID(), now,
  }));
  const imported = [];
  const failed = [];

  if (args.dryRun) {
    console.log(`DRY RUN: nothing is written (project ${PROJECT_ID}, ` +
      `bucket ${args.bucket})`);
    for (const doc of docs) {
      console.log(`would upload ${path.join(args.out, doc.id + ".jpg")} -> ` +
        `${doc.photoPath}; would set recovery_library/${doc.id} ` +
        `(${doc.review}, ${doc.photoStatus})`);
    }
  } else {
    const admin = requireFromFunctions("firebase-admin");
    admin.initializeApp({projectId: PROJECT_ID, storageBucket: args.bucket});
    const bucket = admin.storage().bucket();
    const db = admin.firestore();
    for (const doc of docs) {
      try {
        const token = new URL(doc.photoUrl).searchParams.get("token");
        await bucket.file(doc.photoPath).save(
            fs.readFileSync(path.join(args.out, `${doc.id}.jpg`)), {
              metadata: {
                contentType: "image/jpeg",
                metadata: {firebaseStorageDownloadTokens: token},
              },
            });
        // set, not merge: a re-import resets the doc.
        await db.doc(`recovery_library/${doc.id}`).set(doc);
        imported.push(doc.id);
        console.log(`imported ${doc.id}`);
      } catch (error) {
        failed.push(doc.id);
        console.log(`FAILED ${doc.id}: ${(error && error.message) || error}`);
      }
    }
  }
  const done = args.dryRun ? docs.length : imported.length;
  console.log(`
${args.dryRun ? "would import" : "imported"} ` +
    `${done} of ${seed.length}`);
  console.log(`skipped, photo file missing (${missing.length}): ` +
    missing.join(", "));
  console.log(`failed (${failed.length}): ${failed.join(", ")}`);
  if (failed.length > 0) {
    console.log(`retry with: --only ${failed.join(",")}`);
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = {parseArgs, buildDoc, splitByPhoto, tokenUrl};
