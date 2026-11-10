const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  activePurchase,
  validateRequest,
  reserveQuota,
  remainingQuota,
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
      () => reserveQuota({day: "2026-09-14", daily: 30}, "night", true, now),
      /limit/,
  );
  assert.throws(
      () => reserveQuota({month: "2026-09", total: 300}, "night", true, now),
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

test("Pro drink lookups are capped at fifty a month, unlike reports", () => {
  // The 30-a-day ceiling applies to Pro too, so fifty lookups take more than
  // one day to spend. That is the intended brake: the monthly cap bounds the
  // spend, the daily one stops a single night burning the month.
  let usage = {};
  let spent = 0;
  for (const day of [1, 2, 3]) {
    const now = Date.UTC(2026, 8, day);
    for (let i = 0; i < 20 && spent < 50; i++, spent++) {
      usage = reserveQuota(usage, "lookup", true, now);
    }
  }
  assert.equal(usage.counts.lookup, 50);
  assert.equal(remainingQuota(usage.counts, "lookup", true), 0);
  assert.throws(
      () => reserveQuota(usage, "lookup", true, Date.UTC(2026, 8, 4)),
      /limit/,
  );
  // The month rolls over and the allowance comes back.
  assert.equal(
      reserveQuota(usage, "lookup", true, Date.UTC(2026, 9, 1)).counts.lookup,
      1,
  );
  // A report kind still has no per-kind ceiling for Pro.
  assert.equal(remainingQuota({night: 999}, "night", true), null);
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
