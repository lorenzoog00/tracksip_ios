const {test} = require("node:test");
const assert = require("node:assert/strict");
const {deleteAccount} = require("./accounts");

const NOW = 1700000000000;
const FRESH = NOW / 1000 - 30;

/** Records every write the function makes so tests can assert the order. */
// eslint-disable-next-line require-jsdoc
function fakeDb({owners = [], threads = [], groups = {}} = {}) {
  const calls = {
    tombstone: null,
    recursiveDeleted: [],
    ownerDeletes: [],
    docDeletes: [],
    avatarDeletes: [],
    groupQueries: [],
    threadQueries: [],
    threadSets: [],
  };
  const emptyQuery = {get: () => Promise.resolve({docs: []})};
  // A night_threads ref, enough for removeFromThread's transaction: its
  // queries carry what they ask for so tx.get can answer them.
  const threadRefAt = (path) => ({
    path,
    collection: (name) => ({
      doc: (id) => ({path: `${path}/${name}/${id}`}),
      where: () => ({mine: name, thread: path}),
      orderBy: () => ({limit: () => ({newest: true})}),
    }),
  });
  const parentOf = (path) => threadRefAt(path.split("/").slice(0, 2).join("/"));
  // Docs whose ref deletes itself into docDeletes, as a query result.
  const docsAt = (paths) => ({
    get: () => Promise.resolve({
      docs: paths.map((path) => ({
        ref: {
          path,
          parent: {parent: parentOf(path)},
          delete: () => {
            calls.docDeletes.push(path);
            return Promise.resolve();
          },
        },
      })),
    }),
  });
  // Group docs inside one thread, as transaction query results.
  const groupDocsIn = (name, thread) => {
    const docs = (groups[name] || [])
        .filter((path) => path.startsWith(`${thread}/`))
        .map((path) => ({ref: {path}, data: () => ({uid: "u1"})}));
    return {docs, size: docs.length};
  };
  const runTransaction = async (fn) => fn({
    get: async (target) => {
      if (target.mine) return groupDocsIn(target.mine, target.thread);
      if (target.newest) return {docs: [], size: 0};
      const exists = (groups.reactions || []).includes(target.path);
      return {exists, data: () => ({emoji: "beer"})};
    },
    delete: (ref) => calls.docDeletes.push(ref.path),
    set: (ref) => calls.threadSets.push(ref.path),
  });
  const db = {
    doc: (path) => {
      const ref = {
        path,
        get: () => Promise.resolve({exists: false, data: () => undefined, ref}),
        set: (data) => {
          calls.tombstone = {path, data};
          return Promise.resolve();
        },
        delete: () => {
          calls.docDeletes.push(path);
          return Promise.resolve();
        },
      };
      return ref;
    },
    runTransaction,
    recursiveDelete: (ref) => {
      calls.recursiveDeleted.push(ref.path);
      return Promise.resolve();
    },
    collection: (path) => ({
      get: () => Promise.resolve({docs: []}),
      where: (field, op, value) => {
        if (path === "night_threads") {
          calls.threadQueries.push([field, op, value]);
          return docsAt(threads);
        }
        return path === "purchase_owners" ? {
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
        } : emptyQuery;
      },
    }),
    collectionGroup: (name) => ({
      where: (field, op, value) => {
        calls.groupQueries.push([name, field, op, value]);
        return groups[name] ? docsAt(groups[name]) : emptyQuery;
      },
    }),
  };
  db.bucket = {
    file: (name) => ({
      delete: (options) => {
        calls.avatarDeletes.push({name, options});
        return Promise.resolve();
      },
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
        () => deleteAccount({db, auth, bucket: db.bucket, uid: "u1", authTime, now: NOW}),
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
      db, auth, bucket: db.bucket, uid: "u1", authTime, now: NOW,
    });
    assert.deepEqual(result, {deleted: true});
  }
});

test("a fresh delete writes the tombstone before erasing the user", async () => {
  const {db, calls} = fakeDb({owners: ["o1", "o2"]});
  const {auth, deleted} = fakeAuth();

  const result = await deleteAccount({
    db, auth, bucket: db.bucket, uid: "u1", authTime: FRESH, now: NOW,
  });

  assert.deepEqual(result, {deleted: true});
  // The tombstone blocks writes and late reports while old ID tokens are
  // still valid, so it has to exist before anything is erased.
  assert.deepEqual(calls.tombstone, {
    path: "account_deletions/u1",
    data: {startedAt: NOW},
  });
  // The shared night goes with its ended copies, so recursively.
  assert.deepEqual(calls.recursiveDeleted, [
    "users/u1", "friendships/u1", "blocks/u1", "shared_nights/u1",
  ]);
  assert.deepEqual(calls.ownerDeletes, ["o1", "o2"]);
  // The lock-screen push curve sits outside users/ and holds a device token.
  assert.deepEqual(calls.docDeletes, [
    "live_activities/u1", "push_tokens/u1",
    "notification_prefs/u1",
    "contact_nudges/u1",
    "contact_match_limits/u1",
    "public_profiles/u1",
  ]);
  assert.deepEqual(calls.avatarDeletes, [
    {name: "avatars/u1.jpg", options: {ignoreNotFound: true}},
  ]);
  assert.deepEqual(deleted, ["u1"]);
});

test("a delete removes the user's threads, reactions, comments and prefs", async () => {
  const {db, calls} = fakeDb({
    threads: ["night_threads/u1_5", "night_threads/u1_9"],
    groups: {
      reactions: ["night_threads/f1_7/reactions/u1"],
      comments: [
        "night_threads/f1_7/comments/c1", "night_threads/f2_8/comments/c2",
      ],
    },
  });
  const {auth} = fakeAuth();

  await deleteAccount({
    db, auth, bucket: db.bucket, uid: "u1", authTime: FRESH, now: NOW,
  });

  // Their own nights' threads go whole, subcollections included, without
  // waiting on the shared_nights delete trigger.
  assert.deepEqual(calls.threadQueries, [["owner", "==", "u1"]]);
  assert.deepEqual(calls.recursiveDeleted, [
    "users/u1", "friendships/u1", "blocks/u1", "shared_nights/u1",
    "night_threads/u1_5", "night_threads/u1_9",
  ]);
  // What they left on friends' nights is found by collection-group uid.
  assert.deepEqual(
      calls.groupQueries.filter(([name]) => name !== "blocked"),
      [["reactions", "uid", "==", "u1"], ["comments", "uid", "==", "u1"]],
  );
  // Removed thread by thread, each in one transaction that also clears
  // their rate limit there (summaries are checked in the emulator test).
  assert.deepEqual(calls.docDeletes, [
    "live_activities/u1",
    "night_threads/f1_7/reactions/u1", "night_threads/f1_7/comments/c1",
    "night_threads/f1_7/limits/u1",
    "night_threads/f2_8/comments/c2", "night_threads/f2_8/limits/u1",
    "push_tokens/u1", "notification_prefs/u1",
    "contact_nudges/u1",
    "contact_match_limits/u1",
    "public_profiles/u1",
  ]);
});

test("an already deleted auth user still counts as deleted", async () => {
  const {db} = fakeDb();
  const error = new Error("not found");
  error.code = "auth/user-not-found";
  const {auth} = fakeAuth(error);

  const result = await deleteAccount({
    db, auth, bucket: db.bucket, uid: "u1", authTime: FRESH, now: NOW,
  });

  assert.deepEqual(result, {deleted: true});
});

test("any other auth failure is not reported as a successful delete", async () => {
  const {db} = fakeDb();
  const error = new Error("backend down");
  error.code = "auth/internal-error";
  const {auth} = fakeAuth(error);

  await assert.rejects(
      () => deleteAccount({db, auth, bucket: db.bucket, uid: "u1", authTime: FRESH, now: NOW}),
      /backend down/,
  );
});
