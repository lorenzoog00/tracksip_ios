const {test} = require("node:test");
const assert = require("node:assert/strict");
const {isNewNight, FRESH_MS, COOLDOWN_MS} = require("./night-start");

const NOW = 1764000000000;
const night = (overrides = {}) => ({
  started_at: NOW - 60000, last_drink_at: NOW - 60000, ...overrides,
});

test("a night written for the first time is new", () => {
  assert.equal(isNewNight(undefined, night(), NOW), NOW - 60000);
});

test("a night replacing a different one is new", () => {
  const ended = night({started_at: NOW - 86400000, ended_at: NOW - 80000000});
  assert.equal(isNewNight(ended, night(), NOW), NOW - 60000);
  assert.equal(isNewNight(night({started_at: NOW - 120000}), night(), NOW),
      NOW - 60000);
});

test("another drink on the same night is not new", () => {
  const before = night();
  const after = night({last_drink_at: NOW, drinks: [{name: "Beer"}]});
  assert.equal(isNewNight(before, after, NOW), null);
});

test("a deleted, ended or malformed night is not new", () => {
  assert.equal(isNewNight(night(), undefined, NOW), null);
  assert.equal(isNewNight(undefined, night({ended_at: NOW}), NOW), null);
  for (const started of [undefined, null, "1764000000000", NaN, Infinity]) {
    assert.equal(isNewNight(undefined, night({started_at: started}), NOW),
        null, String(started));
  }
});

test("a night that began over six hours ago is not new", () => {
  assert.equal(FRESH_MS, 6 * 3600000);
  assert.equal(isNewNight(undefined, night({started_at: NOW - FRESH_MS}), NOW),
      NOW - FRESH_MS);
  assert.equal(
      isNewNight(undefined, night({started_at: NOW - FRESH_MS - 1}), NOW),
      null);
});

test("the cooldown is twelve hours", () => {
  assert.equal(COOLDOWN_MS, 12 * 3600000);
});
