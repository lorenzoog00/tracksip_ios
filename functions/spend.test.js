const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {
  maxMonthlySpendMxn,
  MONTHLY_BUDGET_MXN,
  MAX_OUTPUT_TOKENS,
} = require("./report-policy");

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
  // request actually sends.
  const source = readFileSync(`${__dirname}/index.js`, "utf8");
  const match = source.match(/max_tokens:\s*(\d+)/);
  assert.ok(match, "max_tokens not found in index.js");
  assert.equal(
      Number(match[1]),
      MAX_OUTPUT_TOKENS,
      "max_tokens in index.js and MAX_OUTPUT_TOKENS disagree",
  );
});

test("the priced model is the model the request names", () => {
  const source = readFileSync(`${__dirname}/index.js`, "utf8");
  assert.match(
      source,
      /model:\s*"claude-haiku-5-5"/,
      "report-policy.js prices claude-haiku-5-5; index.js names another model",
  );
});
