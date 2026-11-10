const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  activePurchase,
  validateRequest,
  reserveQuota,
  remainingQuota,
  DAILY_REPORT_CAP,
  MONTHLY_REPORT_CAP,
} = require("./report-policy");

test("expired, revoked, upgraded, unknown and undated subscriptions cannot grant Pro", () => {
  const base = {
    productId: "com.lorenzoog.siptrack.pro.monthly",
    expiresDate: 200,
  };
  assert.equal(activePurchase(base, 100), true);
  for (const change of [
    {expiresDate: 100},
    {expiresDate: undefined},
    {revocationDate: 50},
    {isUpgraded: true},
    {productId: "other"},
  ]) {
    assert.equal(activePurchase({...base, ...change}, 100), false);
  }
  assert.equal(
      activePurchase({productId: "com.lorenzoog.siptrack.pro.lifetime"}),
      true,
  );
});

test("free reports cannot exceed five nights by resetting client profile", () => {
  let usage = {};
  for (let i = 0; i < 5; i++) usage = reserveQuota(usage, "night", false, 100);
  assert.throws(() => reserveQuota(usage, "night", false, 100), /limit/);
  assert.equal(
      reserveQuota(usage, "night", false, Date.UTC(2026, 9, 1)).total,
      1,
  );
});

test("paid access still enforces daily and monthly spending limits", () => {
  const now = Date.UTC(2026, 8, 14);
  assert.throws(
      () => reserveQuota({day: "2026-09-14", daily: 150}, "night", true, now),
      /limit/,
  );
  assert.throws(
      () => reserveQuota({month: "2026-09", total: 3000}, "night", true, now),
      /limit/,
  );
});

test("drink lookups stop at five a month without Pro", () => {
  let usage = {};
  for (let i = 0; i < 5; i++) usage = reserveQuota(usage, "lookup", false, 100);
  assert.equal(remainingQuota(usage.counts, "lookup", false), 0);
  assert.throws(() => reserveQuota(usage, "lookup", false, 100), /limit/);
  // Spending the free lookups must not touch the free night reports.
  assert.equal(reserveQuota(usage, "night", false, 100).counts.night, 1);
});

test("Pro drink lookups run until the shared monthly budget is spent", () => {
  // There is no per-kind ceiling for a paying user, lookups included: what
  // they may spend is the monthly budget, shared across reports, lookups and
  // whatever is added later. A lookup costs a fraction of a report, so capping
  // it on its own only withheld calls the budget had already paid for.
  assert.equal(remainingQuota({lookup: 999}, "lookup", true), null);
  assert.equal(remainingQuota({night: 999}, "night", true), null);

  // Well past the old ceiling of fifty, in a single day.
  let usage = {};
  const now = Date.UTC(2026, 8, 14);
  for (let i = 0; i < 120; i++) {
    usage = reserveQuota(usage, "lookup", true, now);
  }
  assert.equal(usage.counts.lookup, 120);

  // The budget's own ceilings are the brake, and they are shared: a month
  // already at the cap turns away a lookup exactly as it would a report.
  assert.throws(
      () => reserveQuota(
          {month: "2026-09", total: MONTHLY_REPORT_CAP}, "lookup", true, now),
      /limit/,
  );
  assert.throws(
      () => reserveQuota(
          {day: "2026-09-14", daily: DAILY_REPORT_CAP}, "lookup", true, now),
      /limit/,
  );

  // Free is untouched: still five a month.
  assert.equal(remainingQuota({}, "lookup", false), 5);
});

test("a lookup cannot be smuggled in as a report kind", () => {
  assert.throws(
      () => validateRequest({kind: "lookup", id: "abc", payload: {drinks: []}}),
      /Invalid report request/,
  );
});

test("reject malformed input and document path traversal before spending", () => {
  const valid = {
    kind: "night",
    id: "abc-123",
    payload: {drinks: [{name: "Beer", quantity: 1}]},
  };
  assert.deepEqual(validateRequest(valid), valid);
  for (const change of [
    {id: "../another-user"},
    {kind: "__proto__"},
    {payload: {drinks: "bad"}},
    {payload: {drinks: [{quantity: -1}]}},
    {payload: {notes: "x".repeat(25000)}},
    {payload: {drinks: [], peakBac: Infinity}},
  ]) {
    assert.throws(() => validateRequest({...valid, ...change}));
  }
});
