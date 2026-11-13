const {test} = require("node:test");
const assert = require("node:assert/strict");
const {FieldValue} = require("firebase-admin/firestore");
const {setAvatar, avatarUrl} = require("./avatar");

const JPEG = Buffer.concat([
  Buffer.from([0xff, 0xd8, 0xff, 0xe0]),
  Buffer.alloc(2000, 7),
]);
const b64 = (buf) => buf.toString("base64");
const CLEAN = {adult: "UNLIKELY", violence: "VERY_UNLIKELY", racy: "POSSIBLE"};

/**
 * @param {boolean} profileExists whether public_profiles/{uid} exists
 * @return {object} a recording fake Firestore
 */
function fakeDb(profileExists = true) {
  const calls = [];
  return {
    calls,
    doc: (path) => ({
      get: async () => ({exists: profileExists}),
      update: async (data) => calls.push({path, data}),
    }),
  };
}

/**
 * @return {object} a recording fake bucket
 */
function fakeBucket() {
  const calls = [];
  return {
    name: "demo.appspot.com",
    calls,
    file: (name) => ({
      save: async (buf, options) => calls.push({op: "save", name, buf, options}),
      delete: async (options) => calls.push({op: "delete", name, options}),
    }),
  };
}

const run = (over = {}) => {
  const db = over.db || fakeDb();
  const bucket = over.bucket || fakeBucket();
  const safeSearch = over.safeSearch || (async () => CLEAN);
  return {
    db,
    bucket,
    promise: setAvatar({
      db,
      bucket,
      uid: "u1",
      data: {jpegBase64: b64(JPEG)},
      safeSearch,
      ...over.args,
    }),
  };
};

test("a clean photo is saved and the profile gets a tokenized URL", async () => {
  const {db, bucket, promise} = run();
  const result = await promise;
  assert.equal(bucket.calls.length, 1);
  const save = bucket.calls[0];
  assert.equal(save.name, "avatars/u1.jpg");
  assert.deepEqual(save.buf, JPEG);
  const token = save.options.metadata.firebaseStorageDownloadTokens;
  assert.match(token, /^[0-9a-f-]{36}$/);
  assert.equal(save.options.contentType, "image/jpeg");
  assert.match(result.photo_url, /^https:\/\/firebasestorage\.googleapis\.com/);
  assert.ok(result.photo_url.includes(`token=${token}`));
  assert.match(result.photo_url, /[?&]v=\d+$/);
  assert.deepEqual(db.calls, [
    {path: "public_profiles/u1", data: {photo_url: result.photo_url}},
  ]);
});

test("avatarUrl is a pure function of bucket, path, token and time", () => {
  assert.equal(
      avatarUrl({bucket: "b", path: "avatars/u1.jpg", token: "t", nowMs: 5}),
      "https://firebasestorage.googleapis.com/v0/b/b/o/avatars%2Fu1.jpg" +
      "?alt=media&token=t&v=5",
  );
});

test("likely adult or violence content rejects and saves nothing", async () => {
  for (const verdict of [
    {...CLEAN, adult: "VERY_LIKELY"},
    {...CLEAN, adult: "LIKELY"},
    {...CLEAN, violence: "LIKELY"},
    {...CLEAN, violence: "VERY_LIKELY"},
    {...CLEAN, racy: "VERY_LIKELY"},
  ]) {
    const {db, bucket, promise} = run({safeSearch: async () => verdict});
    await assert.rejects(
        promise,
        (e) => e.code === "invalid-argument" &&
          e.message === "That photo can't be used.",
    );
    assert.equal(bucket.calls.length, 0);
    assert.equal(db.calls.length, 0);
  }
});

test("racy LIKELY alone is allowed", async () => {
  const {promise} = run({safeSearch: async () => ({...CLEAN, racy: "LIKELY"})});
  assert.ok((await promise).photo_url);
});

test("a safeSearch failure fails closed with nothing saved", async () => {
  const {db, bucket, promise} = run({
    safeSearch: async () => {
      throw new Error("vision down");
    },
  });
  await assert.rejects(promise, (e) => e.code === "unavailable");
  assert.equal(bucket.calls.length, 0);
  assert.equal(db.calls.length, 0);
});

test("a 600 KB photo is rejected before SafeSearch", async () => {
  let checked = false;
  const big = Buffer.concat([JPEG, Buffer.alloc(600 * 1024)]);
  const {bucket, promise} = run({
    args: {data: {jpegBase64: b64(big)}},
    safeSearch: async () => {
      checked = true;
      return CLEAN;
    },
  });
  await assert.rejects(promise, (e) => e.code === "invalid-argument");
  assert.equal(checked, false);
  assert.equal(bucket.calls.length, 0);
});

test("non-JPEG or missing data is rejected", async () => {
  for (const data of [
    {jpegBase64: b64(Buffer.from("not a jpeg at all"))},
    {jpegBase64: ""},
    {jpegBase64: 12},
    {},
    undefined,
  ]) {
    const {bucket, promise} = run({args: {data}});
    await assert.rejects(promise, (e) => e.code === "invalid-argument");
    assert.equal(bucket.calls.length, 0);
  }
});

test("a caller without a profile is told to pick a username", async () => {
  const {bucket, promise} = run({db: fakeDb(false)});
  await assert.rejects(promise, (e) => e.code === "failed-precondition");
  assert.equal(bucket.calls.length, 0);
});

test("null removes the file and clears photo_url", async () => {
  const {db, bucket, promise} = run({args: {data: {jpegBase64: null}}});
  assert.deepEqual(await promise, {photo_url: null});
  assert.deepEqual(bucket.calls, [
    {op: "delete", name: "avatars/u1.jpg", options: {ignoreNotFound: true}},
  ]);
  assert.equal(db.calls.length, 1);
  assert.equal(db.calls[0].path, "public_profiles/u1");
  assert.ok(db.calls[0].data.photo_url.isEqual(FieldValue.delete()));
});
