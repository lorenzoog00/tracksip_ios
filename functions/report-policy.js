const {HttpsError} = require("firebase-functions/v2/https");

const PRODUCTS = new Set([
  "com.lorenzoog.siptrack.pro.monthly",
  "com.lorenzoog.siptrack.pro.yearly",
  "com.lorenzoog.siptrack.pro.lifetime",
]);
// Kinds `requestReport` will answer. `FREE_LIMITS` below also carries the
// drink lookup, which is a different callable, so membership in that table is
// not on its own permission to run a report.
const REPORT_KINDS = new Set([
  "night",
  "recovery",
  "weekly",
  "monthly",
  "comparison",
]);
const FREE_LIMITS = {
  night: 5,
  recovery: 5,
  weekly: 5,
  monthly: 1,
  comparison: 5,
  lookup: 5,
};
// Paid access has no per-kind ceiling at all, drink lookups included: what a
// Pro user may spend is the monthly budget below, shared across reports,
// lookups and anything added later. A lookup costs a fraction of a report, so
// a per-kind cap on top of the budget only took away calls the budget had
// already paid for. `remainingQuota` returns null for every kind here, which
// is how the app knows not to show an allowance.
const PRO_LIMITS = {};

// What one user may cost us in model spend per month. The report caps below
// are counts, so this file states the arithmetic that ties them to money and
// `maxMonthlySpendMxn()` is asserted against the budget by the tests. Change
// the model or the caps and the test says whether it still fits.
//
// Worst case per report, from the request built in index.js: output is hard
// capped by max_tokens, and input is the prompt template (prompts.js is ~2 KB
// in total) plus a fixed list of short numeric fields.
//
// Drink lookups spend the same monthly counter. A lookup asks for less output
// and sends a shorter prompt than a report, so pricing every call at a
// report's worst case stays an upper bound; spend.test.js asserts that no
// request in index.js asks for more output than is priced here.
const MONTHLY_BUDGET_MXN = 15; // the most one user may cost us in a month
const MXN_PER_USD = 20; // deliberately low: fewer dollars bought per budget
const PRICE_INPUT_USD_PER_MTOK = 0.1; // claude-haiku-5-5
const PRICE_OUTPUT_USD_PER_MTOK = 0.5;
// The prompt is what Anthropic bills us for, so the input ceiling is enforced
// on the built prompt and `MAX_INPUT_TOKENS` is *derived* from it. That order
// matters: it used to be a bare 2000 sitting next to a 24 KB payload limit
// that allowed a 6100-token prompt, so `maxMonthlySpendMxn()` understated the
// real worst case by 3x and the 15 MXN budget was not a limit at all. The
// tests could not see it either — they checked the arithmetic against this
// number rather than checking the number against a prompt.
//
// Counted in characters, not tokens: tokenisation is the model's business and
// cannot be reproduced here, so the conversion is deliberately pessimistic at
// 3 characters per token where English prose runs nearer 4.
const CHARS_PER_TOKEN = 3;
// 6000 leaves ~27% headroom over the largest prompt the app can legitimately
// build (a comparison of two nights with six maximal drink groups each, 4702
// characters). `spend.test.js` fails if a prompt change eats that headroom.
const MAX_PROMPT_CHARS = 6000;
const MAX_INPUT_TOKENS = MAX_PROMPT_CHARS / CHARS_PER_TOKEN;
const MAX_OUTPUT_TOKENS = 700; // must match max_tokens in index.js

// The monthly cap is what the budget actually buys: at the worst case priced
// above, 1300 calls is 14.30 MXN. It is the binding limit — 150 a day would
// otherwise allow far more over a month — and spend.test.js fails if the two
// ever drift apart. For a Pro user it is now the *only* limit, so this number
// is the 15 MXN ceiling expressed in calls.
const DAILY_REPORT_CAP = 150;
const MONTHLY_REPORT_CAP = 1300;

// eslint-disable-next-line require-jsdoc
function worstCaseUsdPerReport() {
  return (
    (MAX_INPUT_TOKENS / 1e6) * PRICE_INPUT_USD_PER_MTOK +
    (MAX_OUTPUT_TOKENS / 1e6) * PRICE_OUTPUT_USD_PER_MTOK
  );
}

/** Most a single user can cost in a month, in MXN, if they hit every cap. */
// eslint-disable-next-line require-jsdoc
function maxMonthlySpendMxn() {
  return MONTHLY_REPORT_CAP * worstCaseUsdPerReport() * MXN_PER_USD;
}

/**
 * Refuses a prompt larger than the monthly budget is priced for.
 *
 * Called with the prompt that is about to be sent, after every validation
 * step, because the payload size and the prompt size are not the same thing:
 * a payload well inside the 24 KB limit rendered a prompt three times the
 * priced ceiling. Rather than truncate — which would hand the model an
 * incomplete drink log and produce a confidently wrong report — this refuses,
 * loudly, before anything is spent.
 *
 * @param {string} system The system prompt.
 * @param {string} prompt The user prompt.
 * @return {number} The prompt's size in characters.
 */
function assertPromptFits(system, prompt) {
  const chars = String(system || "").length + String(prompt || "").length;
  if (chars > MAX_PROMPT_CHARS) {
    throw new HttpsError(
        "invalid-argument",
        "There is too much data in this request to summarise.",
    );
  }
  return chars;
}

/**
 * Whether `uid` is on the server-side tester allowlist.
 *
 * A TestFlight subscription is a *sandbox* purchase, and production runs with
 * `APPLE_ALLOW_SANDBOX=false`, so `verifyPurchase` cannot honour it and the
 * tester silently falls to the free tier — paid screens unlocked by local
 * StoreKit, five night reports from the server, and a "limit reached" they
 * cannot explain. Turning sandbox verification on instead would let anyone
 * present a sandbox receipt in production, so the allowlist is the narrow fix.
 *
 * It grants the paid *quota tier* and nothing else: the daily and monthly
 * ceilings still apply, so a listed uid cannot cost more than the budget any
 * paying user may. It is read from server configuration, never from the
 * request, so a client cannot put itself on it.
 *
 * @param {string} uid The caller's Firebase uid.
 * @param {string} raw Comma or whitespace separated uids from configuration.
 * @return {boolean} True when the caller should be billed as a paid account.
 */
function isProTester(uid, raw) {
  if (!uid || typeof raw !== "string") return false;
  return raw
      .split(/[\s,]+/)
      .some((entry) => entry.length > 0 && entry === uid);
}

// eslint-disable-next-line require-jsdoc
function activePurchase(transaction, now = Date.now()) {
  return (
    PRODUCTS.has(transaction.productId) &&
    transaction.revocationDate == null &&
    !transaction.isUpgraded &&
    (transaction.productId.endsWith(".lifetime") ||
      Number(transaction.expiresDate) > now)
  );
}

// eslint-disable-next-line require-jsdoc
function validateRequest(data) {
  if (
    !data ||
    !REPORT_KINDS.has(data.kind) ||
    typeof data.id !== "string" ||
    !/^[a-zA-Z0-9_-]{1,200}$/.test(data.id)
  ) {
    throw new HttpsError("invalid-argument", "Invalid report request.");
  }
  const payload = data.payload;
  if (
    !payload ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    Buffer.byteLength(JSON.stringify(payload)) > 24000
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Report data is too large or invalid.",
    );
  }
  // eslint-disable-next-line require-jsdoc
  function visit(value, depth = 0) {
    if (
      depth > 5 ||
      (typeof value === "number" && !Number.isFinite(value)) ||
      (typeof value === "string" && value.length > 2000) ||
      (Array.isArray(value) && value.length > 100)
    ) {
      throw new HttpsError("invalid-argument", "Invalid report data.");
    }
    if (value && typeof value === "object") {
      for (const child of Object.values(value)) visit(child, depth + 1);
    }
  }
  visit(payload);
  validateAlcoholDose(payload);
  if (data.metadata !== undefined) {
    if (
      !data.metadata ||
      typeof data.metadata !== "object" ||
      Array.isArray(data.metadata)
    ) {
      throw new HttpsError("invalid-argument", "Invalid report metadata.");
    }
    for (const [key, value] of Object.entries(data.metadata)) {
      if (["period_start", "period_end"].includes(key)) {
        if (!Number.isFinite(value) || value < 0 || value > 8640000000000000) {
          throw new HttpsError("invalid-argument", "Invalid report dates.");
        }
      } else if (
        !["event_a_id", "event_b_id"].includes(key) ||
        typeof value !== "string" ||
        !/^[a-zA-Z0-9_-]{1,200}$/.test(value)
      ) {
        throw new HttpsError("invalid-argument", "Invalid report metadata.");
      }
    }
  }
  if (
    data.kind === "night" && payload.alcoholDose === undefined &&
    (!Array.isArray(payload.drinks) ||
      payload.drinks.some(
          (d) =>
            !d ||
          typeof d.name !== "string" ||
          !Number.isInteger(d.quantity) ||
          d.quantity < 0 ||
          d.quantity > 100,
      ))
  ) {
    throw new HttpsError("invalid-argument", "Invalid drinks.");
  }
  if (data.kind === "comparison" && (!payload.eventA || !payload.eventB)) {
    throw new HttpsError("invalid-argument", "Two nights are required.");
  }
  if (data.kind === "comparison") {
    validateAlcoholDose(payload.eventA);
    validateAlcoholDose(payload.eventB);
  }
  return data;
}

// eslint-disable-next-line require-jsdoc
function validateAlcoholDose(data) {
  const dose = data.alcoholDose;
  if (dose === undefined) return;
  const number = (value) => Number.isFinite(value) && value >= 0;
  const count = (value) => Number.isSafeInteger(value) && value >= 0;
  const close = (a, b) => Number.isFinite(b) &&
    Math.abs(a - b) <= Math.max(1, b) * 1e-8;
  const validPour = (pour) => pour && typeof pour.name === "string" &&
    count(pour.quantity) && pour.quantity > 0 &&
    number(pour.volumeMlPerServing) && pour.volumeMlPerServing > 0 &&
    number(pour.abv) && pour.abv <= 100 &&
    number(pour.grams) && number(pour.standardDrinks) &&
    close(pour.grams, pour.volumeMlPerServing * (pour.abv / 100) *
      pour.quantity * 0.789) && close(pour.standardDrinks, pour.grams / 14);
  if (
    !dose || !number(dose.grams) || !number(dose.standardDrinks) ||
    !close(dose.standardDrinks, dose.grams / 14) ||
    !count(dose.loggedServings) || !count(dose.missingServings) ||
    !count(dose.otherGroups) || !number(dose.otherGrams) ||
    (!dose.otherGroups && dose.otherGrams > 0) ||
    !Array.isArray(data.drinks) || data.drinks.length > 6 ||
    !data.drinks.every(validPour) ||
    !close(dose.grams, dose.otherGrams + data.drinks.reduce(
        (sum, pour) => sum + pour.grams, 0)) ||
    (dose.grams > 0 && (!validPour(dose.largestEntry) ||
      dose.largestEntry.grams <= 0 ||
      dose.largestEntry.grams > dose.grams * (1 + 1e-8))) ||
    (dose.grams === 0 && dose.largestEntry !== undefined) ||
    (dose.standardDrinksPerHour !== undefined &&
      !number(dose.standardDrinksPerHour)) ||
    (dose.strongestHourStandardDrinks !== undefined &&
      (!number(dose.strongestHourStandardDrinks) ||
       dose.strongestHourStandardDrinks > dose.standardDrinks * (1 + 1e-8) ||
       !Number.isSafeInteger(dose.strongestHourStartMinute)))
  ) {
    throw new HttpsError("invalid-argument", "Invalid alcohol dose.");
  }
  const covered = dose.missingServings + data.drinks.reduce(
      (sum, pour) => sum + pour.quantity, 0);
  if (covered + dose.otherGroups > dose.loggedServings ||
      (!dose.otherGroups && covered !== dose.loggedServings)) {
    throw new HttpsError("invalid-argument", "Incomplete alcohol dose totals.");
  }
}

// eslint-disable-next-line require-jsdoc
function reserveQuota(usage, kind, pro, now = Date.now()) {
  const month = new Date(now).toISOString().slice(0, 7);
  const day = new Date(now).toISOString().slice(0, 10);
  const counts = usage.month === month ? {...usage.counts} : {};
  const total = usage.month === month ? usage.total || 0 : 0;
  const daily = usage.day === day ? usage.daily || 0 : 0;
  const limit = pro ? PRO_LIMITS[kind] : FREE_LIMITS[kind];
  if (
    daily >= DAILY_REPORT_CAP ||
    total >= MONTHLY_REPORT_CAP ||
    (limit !== undefined && (counts[kind] || 0) >= limit)
  ) {
    throw new HttpsError(
        "resource-exhausted",
        "Your report limit has been reached. Please try again after it resets.",
    );
  }
  counts[kind] = (counts[kind] || 0) + 1;
  return {month, day, counts, total: total + 1, daily: daily + 1};
}

/** How many calls of `kind` are left after `counts` have been spent. */
// eslint-disable-next-line require-jsdoc
function remainingQuota(counts, kind, pro) {
  const limit = pro ? PRO_LIMITS[kind] : FREE_LIMITS[kind];
  if (limit === undefined) return null; // Unlimited for this tier.
  return Math.max(0, limit - (counts[kind] || 0));
}

module.exports = {
  activePurchase,
  isProTester,
  assertPromptFits,
  validateRequest,
  reserveQuota,
  remainingQuota,
  maxMonthlySpendMxn,
  MONTHLY_BUDGET_MXN,
  MAX_OUTPUT_TOKENS,
  MAX_INPUT_TOKENS,
  MAX_PROMPT_CHARS,
  FREE_LIMITS,
  PRO_LIMITS,
  DAILY_REPORT_CAP,
  MONTHLY_REPORT_CAP,
};
