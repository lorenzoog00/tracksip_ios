const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {
  maxMonthlySpendMxn,
  MONTHLY_BUDGET_MXN,
  MAX_OUTPUT_TOKENS,
} = require("./report-policy");
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
