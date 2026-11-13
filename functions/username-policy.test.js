const {test} = require("node:test");
const assert = require("node:assert/strict");
const {normalizeUsername, validateUsername} = require("./username-policy");

test("normalizing trims and lowercases a username", () => {
  assert.equal(normalizeUsername("  Lorenzo "), "lorenzo");
  assert.equal(normalizeUsername("lo.ren_zo9"), "lo.ren_zo9");
});

test("usernames must be 3 to 20 characters of letters, digits, dot or underscore", () => {
  assert.equal(validateUsername("ab").reason, "format");
  assert.equal(validateUsername("a".repeat(21)).reason, "format");
  assert.equal(validateUsername("lo-renzo").reason, "format");
  assert.equal(validateUsername("lo renzo").reason, "format");
  assert.equal(validateUsername("lorenzo@").reason, "format");
  assert.equal(validateUsername("").reason, "format");
  assert.equal(validateUsername(undefined).reason, "format");
  assert.deepEqual(validateUsername("lo.ren_zo9"), {ok: true});
  assert.deepEqual(validateUsername("a".repeat(20)), {ok: true});
  assert.deepEqual(validateUsername("abc"), {ok: true});
});

test("reserved names are blocked only as exact matches", () => {
  for (const name of ["admin", "support", "tracksip", "siptrack", "official", "moderator"]) {
    assert.deepEqual(validateUsername(name), {ok: false, reason: "blocked"});
  }
  // Case and padding do not get around the list.
  assert.deepEqual(validateUsername("  ADMIN "), {ok: false, reason: "blocked"});
  // A reserved word inside a longer name is not reserved.
  assert.deepEqual(validateUsername("xadminx"), {ok: true});
  assert.deepEqual(validateUsername("supportteam"), {ok: true});
});

test("offensive words are blocked even when embedded in a longer name", () => {
  assert.deepEqual(validateUsername("fuck"), {ok: false, reason: "blocked"});
  assert.deepEqual(validateUsername("xxpendejoxx"), {ok: false, reason: "blocked"});
  assert.deepEqual(validateUsername("Mierda.99"), {ok: false, reason: "blocked"});
});
