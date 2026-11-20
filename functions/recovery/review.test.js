const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  isAdmin,
  requireAdmin,
  listPendingPhotos,
  reviewPhoto,
} = require("./review");

/**
 * A tiny Firestore fake: collection().where().get() and doc().get/update.
 * @param {object} docs path -> data
 * @return {object}
 */
function fakeDb(docs) {
  return {
    docs,
    collection: (name) => ({
      where: (field, op, value) => ({
        get: async () => ({
          docs: Object.entries(docs)
              .filter(([path, data]) => path.startsWith(`${name}/`) &&
                op === "==" && data[field] === value)
              .map(([path, data]) => ({
                id: path.slice(name.length + 1),
                data: () => ({...data}),
              })),
        }),
      }),
    }),
    doc: (path) => ({
      get: async () => ({
        exists: path in docs,
        data: () => structuredClone(docs[path]),
      }),
      update: async (fields) => {
        Object.assign(docs[path], fields);
      },
    }),
  };
}

const item = (over) => ({
  name: "Eggs", kind: "breakfast", countries: ["MX"],
  photoUrl: "u", photoStatus: "ready", review: "pending",
  createdAt: 1, ...over,
});

test("isAdmin parses comma and whitespace lists", () => {
  assert.equal(isAdmin("a", "a, b c"), true);
  assert.equal(isAdmin("c", "a, b c"), true);
  assert.equal(isAdmin("d", "a, b c"), false);
  assert.equal(isAdmin("a", ""), false);
  assert.equal(isAdmin(undefined, "a"), false);
});

test("requireAdmin maps auth to the right error", () => {
  assert.throws(() => requireAdmin(undefined, "a"),
      {code: "unauthenticated"});
  assert.throws(() => requireAdmin({uid: "x"}, "a,b"),
      {code: "permission-denied"});
  assert.throws(() => requireAdmin({uid: "a"}, ""),
      {code: "permission-denied"});
  assert.doesNotThrow(() => requireAdmin({uid: "b"}, "a,b"));
});

test("listPendingPhotos returns pending only, newest first, max 50", async () => {
  const docs = {
    "recovery_library/old": item({name: "Old", createdAt: 1}),
    "recovery_library/new": item({name: "New", createdAt: 9}),
    "recovery_library/done": item({review: "approved", createdAt: 99}),
  };
  for (let i = 0; i < 60; i++) {
    docs[`recovery_library/x${i}`] = item({createdAt: 100 + i});
  }
  const {items} = await listPendingPhotos({db: fakeDb(docs)});
  assert.equal(items.length, 50);
  assert.equal(items[0].id, "x59");
  assert.ok(!items.some((entry) => entry.id === "done"));
  assert.deepEqual(Object.keys(items[0]).sort(),
      ["countries", "id", "kind", "name", "photoStatus", "photoUrl"]);
});

test("listPendingPhotos orders Firestore timestamps too", async () => {
  const ts = (ms) => ({toMillis: () => ms});
  const docs = {
    "recovery_library/a": item({createdAt: ts(5)}),
    "recovery_library/b": item({createdAt: ts(7)}),
  };
  const {items} = await listPendingPhotos({db: fakeDb(docs)});
  assert.deepEqual(items.map((entry) => entry.id), ["b", "a"]);
});

test("approve and reject set review", async () => {
  const db = fakeDb({"recovery_library/a": item()});
  assert.deepEqual(
      await reviewPhoto({db, itemId: "a", action: "approve"}), {ok: true});
  assert.equal(db.docs["recovery_library/a"].review, "approved");
  await reviewPhoto({db, itemId: "a", action: "reject"});
  assert.equal(db.docs["recovery_library/a"].review, "rejected");
});

test("regenerate marks generating then runs the generation", async () => {
  for (const status of ["failed", "capped", "ready"]) {
    const db = fakeDb({"recovery_library/a": item({photoStatus: status})});
    const seen = [];
    const out = await reviewPhoto({
      db, itemId: "a", action: "regenerate",
      regenerate: async (id) => {
        seen.push([id, db.docs["recovery_library/a"].photoStatus]);
      },
    });
    assert.deepEqual(out,
        {ok: true, photoStatus: "generating", photoUrl: "u"});
    assert.deepEqual(seen, [["a", "generating"]]);
  }
});

test("bad action and unknown item are refused", async () => {
  const db = fakeDb({"recovery_library/a": item()});
  await assert.rejects(
      reviewPhoto({db, itemId: "a", action: "nuke"}),
      {code: "invalid-argument"});
  await assert.rejects(
      reviewPhoto({db, itemId: "", action: "approve"}),
      {code: "invalid-argument"});
  await assert.rejects(
      reviewPhoto({db, itemId: "zzz", action: "approve"}),
      {code: "not-found"});
});

test("a failed regeneration reports failed without throwing", async () => {
  const db = fakeDb({"recovery_library/a": item()});
  const out = await reviewPhoto({
    db, itemId: "a", action: "regenerate",
    regenerate: async () => {
      db.docs["recovery_library/a"].photoStatus = "failed";
    },
  });
  assert.equal(out.ok, true);
  assert.equal(out.photoStatus, "failed");
});
