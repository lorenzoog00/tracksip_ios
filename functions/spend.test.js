const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {
  maxMonthlySpendMxn,
  assertPromptFits,
  MONTHLY_BUDGET_MXN,
  MAX_OUTPUT_TOKENS,
  MAX_INPUT_TOKENS,
  MAX_PROMPT_CHARS,
} = require("./report-policy");
const {buildPrompt} = require("./prompts");
const {MAX_OUTPUT_TOKENS: LOOKUP_MAX_OUTPUT_TOKENS} = require("./drink-lookup");

// A user who hits every cap is the worst case we pay for. Nothing enforces a
// peso amount at run time — the caps are counts — so the arithmetic that ties
// the two together is asserted here instead. Swap the model for a dearer one,
// or raise a cap, and this test is what says it no longer fits.
test("one user cannot cost more than the monthly budget", () => {
  const worst = maxMonthlySpendMxn();
  assert.ok(
      worst <= MONTHLY_BUDGET_MXN,
      `worst case ${worst.toFixed(2)} MXN exceeds the ` +
      `${MONTHLY_BUDGET_MXN} MXN budget`,
  );
});

test("the budget is not left with absurd headroom either", () => {
  // If the worst case is a rounding error against the budget the caps have
  // drifted far from what they are priced for, and the check above stops
  // meaning anything. This is a smoke alarm, not a target.
  assert.ok(
      maxMonthlySpendMxn() > MONTHLY_BUDGET_MXN / 100,
      "caps are so far under the budget that the pricing is probably stale",
  );
});

// The biggest payload `validateRequest` lets through: arrays are capped at 100
// entries, strings at 2000 characters, and the whole thing at 24000 bytes. The
// 6-group cap in `validateAlcoholDose` does not apply without an alcoholDose,
// which is the legacy shape older clients still send.
const hugeButValidPayload = () => ({
  drinks: Array.from({length: 100}, () => ({
    name: "X".repeat(200),
    quantity: 3,
  })),
  peakBAC: 0.09,
  durationMinutes: 300,
});

// The largest prompt the current app can legitimately produce: a comparison of
// two nights, each with the six drink groups `validateAlcoholDose` allows, at
// the 60-character name limit the client enforces.
const largestLegitimatePayload = () => {
  const pour = (i) => ({
    name: `Cantarito de la casa ${i}`.padEnd(60, "x"),
    quantity: 4,
    volumeMlPerServing: 350,
    abv: 9,
    grams: 24.8,
    standardDrinks: 1.77,
  });
  const night = {
    alcoholDose: {
      grams: 148.8, standardDrinks: 10.6, loggedServings: 24,
      missingServings: 0, otherGroups: 0, otherGrams: 0,
      standardDrinksPerHour: 1.8, strongestHourStandardDrinks: 3.1,
      strongestHourStartMinute: 180, largestEntry: pour(1),
    },
    drinks: [1, 2, 3, 4, 5, 6].map(pour),
    peakBAC: 0.14, durationMinutes: 420, water: 750, calories: 2000,
  };
  return {eventA: night, eventB: night};
};

test("the priced input ceiling is one the prompt cannot exceed", () => {
  // The bug this exists for: MAX_INPUT_TOKENS was a bare 2000 that nothing
  // enforced. A payload inside the 24 KB limit built a ~6100-token prompt, so
  // the real worst case was 25 MXN against a 15 MXN budget — and the tests
  // above could not see it, because they check the arithmetic against this
  // number rather than the number against a prompt.
  const payload = hugeButValidPayload();
  assert.ok(
      Buffer.byteLength(JSON.stringify(payload)) <= 24000,
      "this payload is meant to be one validateRequest accepts",
  );
  const prompt = buildPrompt("night", payload);
  assert.ok(
      (prompt.system + prompt.prompt).length > MAX_PROMPT_CHARS,
      "the payload no longer builds an oversized prompt; rewrite this test " +
      "rather than deleting it, or the ceiling stops being tested at all",
  );
  assert.throws(() => assertPromptFits(prompt.system, prompt.prompt), {
    message: /too much data/,
  });
});

test("every prompt the app can legitimately build still fits", () => {
  // The other side of the guard: a ceiling that rejects real nights is an
  // outage. This fails if a prompt grows into the headroom.
  const comparison = buildPrompt("comparison", largestLegitimatePayload());
  const chars = assertPromptFits(comparison.system, comparison.prompt);
  assert.ok(
      chars < MAX_PROMPT_CHARS * 0.9,
      `the largest legitimate prompt is ${chars} of ${MAX_PROMPT_CHARS} ` +
      "characters — raise the ceiling and reprice, or shorten the prompt",
  );
});

test("the priced input ceiling is derived from the enforced one", () => {
  // Not an identity: MAX_INPUT_TOKENS is what the budget is computed from, so
  // it has to come from the limit that is actually checked. Set them apart and
  // the budget silently stops meaning anything.
  assert.ok(MAX_INPUT_TOKENS > 0);
  assert.ok(
      MAX_INPUT_TOKENS * 3 <= MAX_PROMPT_CHARS,
      "pricing assumes more input than the prompt guard permits",
  );
});

test("the priced output ceiling matches the request", () => {
  // The budget is only honest while the number it prices is the number the
  // request actually sends. Every callable in index.js shares the monthly
  // call counter the budget is built on, so none of them may ask for more
  // output than that counter is priced for.
  const source = readFileSync(`${__dirname}/index.js`, "utf8");
  const asked = [...source.matchAll(/max_tokens:\s*(\d+)/g)].map(
      (match) => Number(match[1]),
  );
  assert.ok(asked.length >= 2, "expected a report and a lookup in index.js");
  for (const tokens of asked) {
    assert.ok(
        tokens <= MAX_OUTPUT_TOKENS,
        `max_tokens ${tokens} exceeds the priced ${MAX_OUTPUT_TOKENS}`,
    );
  }
  assert.ok(
      asked.includes(MAX_OUTPUT_TOKENS),
      "no request actually uses the ceiling the budget is priced at",
  );
  assert.ok(
      asked.includes(LOOKUP_MAX_OUTPUT_TOKENS),
      "max_tokens for the lookup and drink-lookup.js disagree",
  );
});

test("the priced model is the model the request names", () => {
  const source = readFileSync(`${__dirname}/index.js`, "utf8");
  const models = [...source.matchAll(/model:\s*"([^"]+)"/g)].map((m) => m[1]);
  assert.ok(models.length >= 2, "expected a report and a lookup in index.js");
  for (const model of models) {
    assert.equal(
        model,
        "claude-haiku-5-5",
        `report-policy.js prices claude-haiku-5-5; index.js uses ${model}`,
    );
  }
});
