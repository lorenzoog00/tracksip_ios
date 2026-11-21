// Shared paths and helpers for the recovery photo library scripts.
const fs = require("node:fs");
const path = require("node:path");
const {createRequire} = require("node:module");

const repoRoot = path.resolve(__dirname, "..", "..");
const functionsDir = path.join(repoRoot, "functions");
const SEED_PATH = path.join(functionsDir, "recovery", "library-seed.json");
const DEFAULT_OUT_DIR = path.join(repoRoot, "output", "recovery-library");
const PROJECT_ID = "device-streaming-8326abff";
const DEFAULT_MODEL = "gemini-3.1-flash-image";

// Resolves packages (firebase-admin, @google/genai, sharp) from functions/.
const requireFromFunctions = createRequire(
    path.join(functionsDir, "package.json"));

/** @return {object[]} The seed items. */
function loadSeed(seedPath = SEED_PATH) {
  return JSON.parse(fs.readFileSync(seedPath, "utf8"));
}

/**
 * Minimal `--flag value` / `--flag` parser. Flags in `booleans` take no value.
 * @param {string[]} argv
 * @param {string[]} booleans
 * @param {string[]} valued Flags that take a value. Anything else throws, so
 *   a typo can never silently drop a safety flag.
 * @return {object} Flag values keyed by name.
 */
function parseFlags(argv, booleans, valued) {
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) throw new Error(`Unexpected argument: ${arg}`);
    const name = arg.slice(2);
    if (!booleans.includes(name) && !valued.includes(name)) {
      throw new Error(`Unknown flag: --${name}`);
    }
    if (booleans.includes(name)) {
      flags[name] = true;
    } else {
      const value = argv[++i];
      if (value === undefined || value.startsWith("--")) {
        throw new Error(`Missing value for --${name}`);
      }
      flags[name] = value;
    }
  }
  return flags;
}

module.exports = {
  repoRoot, functionsDir, SEED_PATH, DEFAULT_OUT_DIR, PROJECT_ID,
  DEFAULT_MODEL, requireFromFunctions, loadSeed, parseFlags,
};
