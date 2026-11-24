const {test} = require("node:test");
const assert = require("node:assert/strict");
const {lookupPhoneOwners} = require("./social");

/**
 * A stand-in for firebase-admin Auth. Every getUsers call is recorded, along
 * with the most calls that were ever in flight at once.
 * @param {Function} answer (identifiers, callIndex) => the call's result;
 *     throwing rejects that call
 * @return {object} {auth, calls, peak}: the stand-in, each call's
 *     identifiers, and peak() for the most calls in flight at once
 */
function fakeAuth(answer) {
  const calls = [];
  let inFlight = 0;
  let peak = 0;
  return {
    calls,
    peak: () => peak,
    auth: {
      getUsers: async (identifiers) => {
        const index = calls.push(identifiers) - 1;
        inFlight++;
        peak = Math.max(peak, inFlight);
        try {
          await Promise.resolve();
          return answer(identifiers, index);
        } finally {
          inFlight--;
        }
      },
    },
  };
}

/**
 * A logger that keeps what warn() was given.
 * @return {object} {log, warnings}: the logger and each warn() call's args
 */
function recordingLog() {
  const warnings = [];
  return {warnings, log: {warn: (...args) => warnings.push(args)}};
}

const phone = (n) => `+1415555${String(n).padStart(4, "0")}`;
const phones = (count) => Array.from({length: count}, (_, i) => phone(i));
const found = (ids) => ({
  users: ids.map(({phoneNumber}) => ({uid: `u${phoneNumber}`, phoneNumber})),
  notFound: [],
});

test("phone lookups go out 100 at a time, at most five at once", async () => {
  const asked = phones(701);
  const {auth, calls, peak} = fakeAuth(found);
  const {log, warnings} = recordingLog();
  const owners = await lookupPhoneOwners({auth, phones: asked, log});
  assert.deepEqual(calls.map((c) => c.length),
      [100, 100, 100, 100, 100, 100, 100, 1]);
  assert.deepEqual(calls.flat().map((c) => c.phoneNumber), asked);
  assert.equal(peak(), 5);
  assert.equal(owners.length, 701);
  assert.deepEqual(owners[0], {uid: `u${phone(0)}`, phone: phone(0)});
  assert.equal(warnings.length, 0);
});

test("disabled accounts are never matched", async () => {
  const {auth} = fakeAuth((ids) => ({
    users: ids.map(({phoneNumber}) => ({
      uid: `u${phoneNumber}`, phoneNumber, disabled: phoneNumber === phone(1),
    })),
    notFound: [],
  }));
  const owners = await lookupPhoneOwners({
    auth, phones: phones(3), log: recordingLog().log,
  });
  assert.deepEqual(owners.map((o) => o.phone), [phone(0), phone(2)]);
});

test("a failed lookup batch is skipped and the others still answer", async () => {
  // Seven batches: the second of the first wave and the first of the second
  // fail, with the numbers in the error the way a real one might quote them.
  const {auth, calls} = fakeAuth((ids, index) => {
    if (index === 1 || index === 5) {
      throw new Error(`lookup failed for ${ids[0].phoneNumber}`);
    }
    return found(ids);
  });
  const {log, warnings} = recordingLog();
  const owners = await lookupPhoneOwners({auth, phones: phones(700), log});
  assert.equal(calls.length, 7);
  assert.equal(owners.length, 500);
  const matched = new Set(owners.map((o) => o.phone));
  assert.ok(!matched.has(phone(100)) && !matched.has(phone(199)));
  assert.ok(!matched.has(phone(500)) && !matched.has(phone(599)));
  assert.ok(matched.has(phone(200)) && matched.has(phone(699)));
  assert.equal(warnings.length, 1);
  assert.deepEqual(warnings[0][1], {failed: 2, batches: 7});
  assert.ok(!JSON.stringify(warnings).includes("+1415"),
      "a warning must never carry a phone number");
});

test("no numbers means no lookups", async () => {
  const {auth, calls} = fakeAuth(found);
  const owners = await lookupPhoneOwners({
    auth, phones: [], log: recordingLog().log,
  });
  assert.deepEqual(owners, []);
  assert.equal(calls.length, 0);
});

const {validateDisplayName} = require("./social");

test("validateDisplayName trims and keeps ordinary names", () => {
  assert.equal(validateDisplayName("  Lorenzo Orozco "), "Lorenzo Orozco");
  assert.equal(validateDisplayName("🍻🍻"), "🍻🍻");
  assert.equal(validateDisplayName("a".repeat(30)), "a".repeat(30));
});

test("validateDisplayName returns null for empty or non-string input", () => {
  assert.equal(validateDisplayName("   "), null);
  assert.equal(validateDisplayName(""), null);
  assert.equal(validateDisplayName(undefined), null);
});

test("validateDisplayName rejects long, control and moderated names", () => {
  assert.throws(
      () => validateDisplayName("a".repeat(31)),
      (e) => e.code === "invalid-argument" &&
        e.message === "Names can be up to 30 characters.",
  );
  for (const bad of ["a\u0007b", "line\nbreak", "Big Shit Lord"]) {
    assert.throws(
        () => validateDisplayName(bad),
        (e) => e.code === "invalid-argument" &&
          e.message === "Try a different name.",
        bad,
    );
  }
});
