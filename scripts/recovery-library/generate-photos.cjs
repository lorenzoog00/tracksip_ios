#!/usr/bin/env node
//
// Generates one photo per recovery library seed item into
// output/recovery-library/{id}.jpg. Resumable: existing files are skipped
// unless their id is listed in --only.
//
// Usage: node scripts/recovery-library/generate-photos.cjs
//          [--only id1,id2] [--concurrency 4] [--model <id>] [--out <dir>]
// Uses Application Default Credentials. RECOVERY_FAKE_IMAGES=1 writes small
// solid-color JPEGs instead of calling the model (no network).
const fs = require("node:fs");
const path = require("node:path");
const {
  DEFAULT_OUT_DIR, PROJECT_ID, DEFAULT_MODEL, requireFromFunctions,
  loadSeed, parseFlags,
} = require("./common.cjs");

/**
 * @param {string[]} argv
 * @return {{only: ?string[], concurrency: number, model: string, out: string}}
 */
function parseArgs(argv) {
  const flags = parseFlags(argv, [], ["only", "concurrency", "model", "out"]);
  const concurrency = flags.concurrency === undefined ?
    4 : Number(flags.concurrency);
  if (!Number.isInteger(concurrency) || concurrency < 1) {
    throw new Error("--concurrency must be a positive integer");
  }
  return {
    only: flags.only === undefined ? null :
      flags.only.split(",").map((id) => id.trim()).filter(Boolean),
    concurrency,
    model: flags.model ?? DEFAULT_MODEL,
    out: flags.out ? path.resolve(flags.out) : DEFAULT_OUT_DIR,
  };
}

/**
 * Which seed items to generate. Without `only`, everything that has no file
 * yet; with `only`, exactly those ids (regenerated even if a file exists).
 * @param {{id: string}[]} seed
 * @param {Set<string>} existing ids that already have a file
 * @param {?string[]} only
 * @return {{toGenerate: object[], skipped: string[]}}
 */
function selectItems(seed, existing, only) {
  if (only) {
    const known = new Set(seed.map((item) => item.id));
    const unknown = only.filter((id) => !known.has(id));
    if (unknown.length > 0) {
      throw new Error(`Unknown ids in --only: ${unknown.join(", ")}`);
    }
    const wanted = new Set(only);
    return {
      toGenerate: seed.filter((item) => wanted.has(item.id)),
      skipped: [],
    };
  }
  return {
    toGenerate: seed.filter((item) => !existing.has(item.id)),
    skipped: seed.filter((item) => existing.has(item.id))
        .map((item) => item.id),
  };
}

/** @return {Set<string>} ids with a {id}.jpg in `dir`. */
function existingIds(dir) {
  if (!fs.existsSync(dir)) return new Set();
  return new Set(fs.readdirSync(dir)
      .filter((name) => name.endsWith(".jpg"))
      .map((name) => name.slice(0, -4)));
}

/** A small solid-color JPEG, a different color per id. */
async function fakePhoto({id}) {
  const sharp = requireFromFunctions("sharp");
  let hash = 0;
  for (const ch of id) hash = (hash * 31 + ch.charCodeAt(0)) >>> 0;
  return sharp({
    create: {
      width: 80, height: 60, channels: 3,
      background: {r: hash & 255, g: (hash >> 8) & 255, b: (hash >> 16) & 255},
    },
  }).jpeg().toBuffer();
}

/**
 * Runs `work` over `items` with at most `concurrency` in flight. Failures are
 * collected, never thrown.
 * @param {object[]} items
 * @param {number} concurrency
 * @param {Function} work (item) => Promise
 * @param {Function} log
 * @return {Promise<{generated: string[], failed: object[]}>}
 */
async function runPool(items, concurrency, work, log = () => {}) {
  const generated = [];
  const failed = [];
  let next = 0;
  /** Takes items until none are left. */
  async function worker() {
    while (next < items.length) {
      const item = items[next++];
      try {
        await work(item);
        generated.push(item.id);
        log(`ok     ${item.id}`);
      } catch (error) {
        const message = String((error && error.message) || error);
        failed.push({id: item.id, error: message});
        log(`FAILED ${item.id}: ${message}`);
      }
    }
  }
  await Promise.all(Array.from(
      {length: Math.min(concurrency, items.length)}, worker));
  return {generated, failed};
}

/**
 * @param {{model: string}} options
 * @return {Function} (item) => Promise<Buffer>
 */
function makeGenerator({model}) {
  if (process.env.RECOVERY_FAKE_IMAGES === "1") return fakePhoto;
  const {GoogleGenAI} = requireFromFunctions("@google/genai");
  const {generatePhoto} = require("../../functions/recovery/image");
  const genai = new GoogleGenAI({
    // Same endpoint as the runtime trigger: Gemini 3.x image models are
    // served only from "global".
    vertexai: true, project: PROJECT_ID, location: "global",
  });
  return (item) => generatePhoto(item, {genai, model});
}

/** @param {string[]} argv */
async function main(argv) {
  const args = parseArgs(argv);
  fs.mkdirSync(args.out, {recursive: true});
  const seed = loadSeed();
  const {toGenerate, skipped} =
    selectItems(seed, existingIds(args.out), args.only);
  console.log(`seed ${seed.length}, to generate ${toGenerate.length}, ` +
    `skipped ${skipped.length}, concurrency ${args.concurrency}` +
    (process.env.RECOVERY_FAKE_IMAGES === "1" ? " (FAKE images)" : ""));
  const generate = makeGenerator(args);
  const {generated, failed} = await runPool(
      toGenerate, args.concurrency,
      async (item) => {
        const buffer = await generate(item);
        fs.writeFileSync(path.join(args.out, `${item.id}.jpg`), buffer);
      },
      console.log);
  console.log("\nSummary");
  console.log(`generated (${generated.length}): ${generated.join(", ")}`);
  console.log(`skipped   (${skipped.length}): ${skipped.join(", ")}`);
  console.log(`failed    (${failed.length}): ` +
    failed.map((f) => `${f.id} [${f.error}]`).join(", "));
  if (failed.length > 0) process.exitCode = 1;
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

module.exports = {parseArgs, selectItems, existingIds, runPool, fakePhoto};
