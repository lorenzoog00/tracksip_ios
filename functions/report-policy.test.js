const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  activePurchase,
  validateRequest,
  reserveQuota,
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
