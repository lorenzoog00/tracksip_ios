const {test} = require("node:test");
const assert = require("node:assert/strict");
const {deleteAccount} = require("./accounts");

const NOW = 1700000000000;
const FRESH = NOW / 1000 - 30;

/** Records every write the function makes so tests can assert the order. */
// eslint-disable-next-line require-jsdoc
function fakeDb({owners = []} = {}) {
  const calls = {tombstone: null, recursiveDeleted: [], ownerDeletes: []};
  const db = {
    doc: (path) => ({
      path,
      set: (data) => {
        calls.tombstone = {path, data};
        return Promise.resolve();
      },
    }),
    recursiveDelete: (ref) => {
      calls.recursiveDeleted.push(ref.path);
      return Promise.resolve();
    },
    collection: () => ({
      where: () => ({
        get: () => Promise.resolve({
          docs: owners.map((id) => ({
            ref: {
              delete: () => {
                calls.ownerDeletes.push(id);
                return Promise.resolve();
              },
            },
          })),
        }),
      }),
    }),
  };
  return {db, calls};
}

// eslint-disable-next-line require-jsdoc
function fakeAuth(error) {
  const deleted = [];
  return {
    deleted,
    auth: {
      deleteUser: (uid) => {
        if (error) return Promise.reject(error);
        deleted.push(uid);
        return Promise.resolve();
      },
    },
  };
}

// A delete is only accepted on a freshly re-authenticated token. The iOS client
// re-authenticates first (interactively for Apple/Google, with the password for
// password accounts) precisely to satisfy this window.
test("a stale, absent or future auth_time cannot delete an account", async () => {
  for (const authTime of [
    NOW / 1000 - 301, // older than the five minute window
    NOW / 1000 - 10000,
    NOW / 1000 + 61, // further ahead than the allowed clock skew
    undefined,
    NaN,
    Infinity,
    "1700000000",
  ]) {
    const {db, calls} = fakeDb();
    const {auth, deleted} = fakeAuth();
    await assert.rejects(
        () => deleteAccount({db, auth, uid: "u1", authTime, now: NOW}),
        (error) => error.code === "unauthenticated" ||
          error.httpErrorCode?.status === 401,
    );
    // Nothing may be touched when the token is not fresh enough.
    assert.equal(calls.tombstone, null);
    assert.deepEqual(calls.recursiveDeleted, []);
    assert.deepEqual(deleted, []);
  }
});

test("a window edge auth_time is accepted", async () => {
  for (const authTime of [NOW / 1000 - 300, NOW / 1000, NOW / 1000 + 60]) {
    const {db} = fakeDb();
    const {auth} = fakeAuth();
    const result = await deleteAccount({
      db, auth, uid: "u1", authTime, now: NOW,
    });
    assert.deepEqual(result, {deleted: true});
  }
});

test("a fresh delete writes the tombstone before erasing the user", async () => {
  const {db, calls} = fakeDb({owners: ["o1", "o2"]});
  const {auth, deleted} = fakeAuth();

  const result = await deleteAccount({
    db, auth, uid: "u1", authTime: FRESH, now: NOW,
  });

  assert.deepEqual(result, {deleted: true});
  // The tombstone blocks writes and late reports while old ID tokens are
  // still valid, so it has to exist before anything is erased.
  assert.deepEqual(calls.tombstone, {
    path: "account_deletions/u1",
    data: {startedAt: NOW},
  });
  assert.deepEqual(calls.recursiveDeleted, ["users/u1"]);
  assert.deepEqual(calls.ownerDeletes, ["o1", "o2"]);
  assert.deepEqual(deleted, ["u1"]);
});

test("an already deleted auth user still counts as deleted", async () => {
  const {db} = fakeDb();
  const error = new Error("not found");
  error.code = "auth/user-not-found";
  const {auth} = fakeAuth(error);

  const result = await deleteAccount({
    db, auth, uid: "u1", authTime: FRESH, now: NOW,
  });

  assert.deepEqual(result, {deleted: true});
});

test("any other auth failure is not reported as a successful delete", async () => {
  const {db} = fakeDb();
  const error = new Error("backend down");
  error.code = "auth/internal-error";
  const {auth} = fakeAuth(error);

  await assert.rejects(
      () => deleteAccount({db, auth, uid: "u1", authTime: FRESH, now: NOW}),
      /backend down/,
  );
});
