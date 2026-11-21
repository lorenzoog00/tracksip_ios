const {test} = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");
const {execFileSync} = require("node:child_process");
const sharp = require("sharp");
const {
  PHOTO_STYLE,
  PHOTO_CACHE_CONTROL,
  photoPrompt,
  generatePhoto,
  completeLibraryPhoto,
  withPhoto,
} = require("./image");

const PLAN_PATH = "users/u1/night_recoveries/e1";
const NOW = 1700000000000;

/**
 * A tiny in-memory Firestore: doc(path).get/update, with the not-found
 * error `update` raises for a missing doc.
 * @param {object} docs path -> data
 * @return {object}
 */
function fakeDb(docs) {
  const updates = [];
  // Like Firestore, transactions run one after another; plain reads yield
  // first, so an unguarded read-modify-write interleaves.
  let queue = Promise.resolve();
  return {
    docs,
    updates,
    runTransaction: (fn) => {
      const run = queue.then(() => fn({
        get: (ref) => ref.get(),
        update: (ref, fields) => ref.update(fields),
      }));
      queue = run.catch(() => {});
      return run;
    },
    doc: (path) => ({
      get: async () => {
        const copy = structuredClone(docs[path]);
        await new Promise((resolve) => setTimeout(resolve, 1));
        return {exists: path in docs, data: () => copy};
      },
      update: async (fields) => {
        if (!(path in docs)) {
          throw Object.assign(new Error("NOT_FOUND"), {code: 5});
        }
        updates.push(path);
        docs[path] = {...docs[path], ...fields};
      },
    }),
  };
}

/**
 * @return {{saved: object[], name: string, file: Function}}
 */
function fakeBucket() {
  const saved = [];
  return {
    name: "demo-bucket",
    saved,
    file: (path) => ({
      save: async (buffer, options) => saved.push({path, buffer, options}),
    }),
  };
}

const libraryItem = (extra = {}) => ({
  name: "Banana pancakes",
  kind: "breakfast",
  photoStatus: "generating",
  photoUrl: null,
  review: "pending",
  pendingPlanPaths: [PLAN_PATH],
  ...extra,
});

const planDoc = () => ({
  type: "morning",
  plan: {
    headline: "h",
    breakfast: {itemId: "other", name: "Toast", photoUrl: "https://t"},
    activities: [
      {itemId: "a1", name: "Walk", photoUrl: null},
      {itemId: "item1", name: "Open window", photoUrl: null},
    ],
  },
});

const noWait = async () => {};

test("photoPrompt carries the style and the name", () => {
  const breakfast = photoPrompt({name: "Banana pancakes", kind: "breakfast"});
  assert.equal(breakfast, `${PHOTO_STYLE} Subject: Banana pancakes.`);
  const activity = photoPrompt({name: "A rumpled bed", kind: "activity"});
  // Activities are real-size scenes: never "on a table" (which shrank
  // places into dioramas) and never with readable words.
  assert.match(activity, /Scene: A rumpled bed\.$/);
  assert.match(activity, /full-size/);
  assert.match(activity, /Not a miniature, model, diorama or toy/);
  assert.match(activity, /No readable words/);
  assert.match(activity, /No people/);
  assert.doesNotMatch(activity, /stone table/);
});

test("loading the module does not load sharp", () => {
  // index.js requires this file, so a top-level sharp would load its native
  // module on every function's cold start. This file loads sharp itself, so
  // the check runs in a fresh process.
  const script = `require(${JSON.stringify(path.join(__dirname, "image.js"))});` +
    "const loaded = Object.keys(require.cache)" +
    ".some((p) => /[\\\\/]node_modules[\\\\/]sharp[\\\\/]/.test(p));" +
    "process.stdout.write(String(loaded));";
  const out = execFileSync(process.execPath, ["-e", script], {
    encoding: "utf8",
  });
  assert.equal(out, "false");
});

test("withPhoto sets the matching entry only and leaves the input alone", () => {
  const plan = planDoc().plan;
  const next = withPhoto(plan, "item1", "https://p");
  assert.equal(next.activities[1].photoUrl, "https://p");
  assert.equal(next.activities[0].photoUrl, null);
  assert.equal(next.breakfast.photoUrl, "https://t");
  assert.equal(plan.activities[1].photoUrl, null);
  const bf = withPhoto(plan, "other", "https://q");
  assert.equal(bf.breakfast.photoUrl, "https://q");
});

test("generatePhoto asks for 4:3 at 1K and returns an 800 px JPEG", async () => {
  const png = await sharp({
    create: {width: 1200, height: 900, channels: 3, background: "#884422"},
  }).png().toBuffer();
  let request;
  const genai = {
    models: {
      generateContent: async (req) => {
        request = req;
        return {candidates: [{content: {parts: [
          {text: "here"},
          {inlineData: {data: png.toString("base64"), mimeType: "image/png"}},
        ]}}]};
      },
    },
  };
  const out = await generatePhoto(
      {name: "Banana pancakes", kind: "breakfast"}, {genai, model: "m-1"});
  assert.equal(request.model, "m-1");
  assert.equal(request.contents, `${PHOTO_STYLE} Subject: Banana pancakes.`);
  assert.equal(request.config.imageConfig.aspectRatio, "4:3");
  assert.equal(request.config.imageConfig.imageSize, "1K");
  const meta = await sharp(out).metadata();
  assert.equal(meta.format, "jpeg");
  assert.equal(meta.width, 800);
});

test("generatePhoto throws when the model returns no image", async () => {
  const genai = {models: {generateContent: async () => ({
    candidates: [{content: {parts: [{text: "I can't."}]}}],
  })}};
  await assert.rejects(generatePhoto(
      {name: "x", kind: "breakfast"}, {genai, model: "m"}));
});

test("completeLibraryPhoto stores the photo and fills the waiting plan",
    async () => {
      const db = fakeDb({
        "recovery_library/item1": libraryItem({name: "Open window",
          kind: "activity"}),
        [PLAN_PATH]: planDoc(),
      });
      const bucket = fakeBucket();
      const jpeg = Buffer.from([0xff, 0xd8, 0xff]);
      let asked;
      await completeLibraryPhoto({
        db, bucket, itemId: "item1", now: NOW, wait: noWait,
        generate: async (item) => {
          asked = item;
          return jpeg;
        },
      });
      assert.deepEqual(asked, {name: "Open window", kind: "activity"});
      assert.equal(bucket.saved.length, 1);
      const {path, buffer, options} = bucket.saved[0];
      assert.equal(path, "recovery-library/item1.jpg");
      assert.equal(buffer, jpeg);
      assert.equal(options.metadata.contentType, "image/jpeg");
      // Cached for a year: each path and token is never reused for another
      // photo. The token stays custom metadata, or the URL stops working.
      assert.equal(options.metadata.cacheControl,
          "public, max-age=31536000, immutable");
      assert.equal(PHOTO_CACHE_CONTROL, options.metadata.cacheControl);
      const token = options.metadata.metadata.firebaseStorageDownloadTokens;
      assert.match(token, /^[0-9a-f-]{36}$/);
      assert.deepEqual(Object.keys(options.metadata.metadata),
          ["firebaseStorageDownloadTokens"]);
      const item = db.docs["recovery_library/item1"];
      assert.equal(item.photoStatus, "ready");
      assert.equal(item.photoUrl,
          "https://firebasestorage.googleapis.com/v0/b/demo-bucket/o/" +
          "recovery-library%2Fitem1.jpg?alt=media&token=" + token +
          "&v=" + NOW);
      assert.deepEqual(item.pendingPlanPaths, []);
      const plan = db.docs[PLAN_PATH].plan;
      assert.equal(plan.activities[1].photoUrl, item.photoUrl);
      assert.equal(plan.activities[0].photoUrl, null);
      assert.equal(plan.breakfast.photoUrl, "https://t");
    });

test("a failed generation marks the item failed and leaves the plan",
    async () => {
      const db = fakeDb({
        "recovery_library/item1": libraryItem(),
        [PLAN_PATH]: planDoc(),
      });
      const bucket = fakeBucket();
      await completeLibraryPhoto({
        db, bucket, itemId: "item1", now: NOW, wait: noWait,
        generate: async () => {
          throw new Error("blocked");
        },
      });
      const item = db.docs["recovery_library/item1"];
      assert.equal(item.photoStatus, "failed");
      assert.equal(item.photoUrl, null);
      assert.deepEqual(item.pendingPlanPaths, []);
      assert.equal(bucket.saved.length, 0);
      assert.ok(db.updates.every((p) => p === "recovery_library/item1"));
      assert.equal(db.docs[PLAN_PATH].plan.activities[1].photoUrl, null);
    });

test("a deleted plan doc is not recreated", async () => {
  const db = fakeDb({"recovery_library/item1": libraryItem()});
  const waits = [];
  await completeLibraryPhoto({
    db, bucket: fakeBucket(), itemId: "item1", now: NOW,
    wait: async (ms) => waits.push(ms),
    generate: async () => Buffer.from("x"),
  });
  assert.ok(!(PLAN_PATH in db.docs));
  assert.deepEqual(waits, [5000]);
  const item = db.docs["recovery_library/item1"];
  assert.equal(item.photoStatus, "ready");
  assert.deepEqual(item.pendingPlanPaths, []);
});

test("a plan doc written a moment late is filled on the retry", async () => {
  const db = fakeDb({"recovery_library/item1": libraryItem()});
  await completeLibraryPhoto({
    db, bucket: fakeBucket(), itemId: "item1", now: NOW,
    wait: async () => {
      db.docs[PLAN_PATH] = planDoc();
    },
    generate: async () => Buffer.from("x"),
  });
  assert.ok(db.docs[PLAN_PATH].plan.activities[1].photoUrl);
});

test("an item that is not generating is left alone", async () => {
  const db = fakeDb({
    "recovery_library/item1": libraryItem({photoStatus: "ready"}),
  });
  let called = false;
  await completeLibraryPhoto({
    db, bucket: fakeBucket(), itemId: "item1", now: NOW, wait: noWait,
    generate: async () => {
      called = true;
      return Buffer.from("x");
    },
  });
  assert.equal(called, false);
  assert.deepEqual(db.updates, []);
});

test("two items waiting on one plan both get their photo", async () => {
  const db = fakeDb({
    "recovery_library/item1": libraryItem({name: "Open window",
      kind: "activity"}),
    "recovery_library/item2": libraryItem({name: "Walk", kind: "activity"}),
    [PLAN_PATH]: {plan: {
      breakfast: {itemId: "b", name: "Toast", photoUrl: null},
      activities: [
        {itemId: "item1", name: "Open window", photoUrl: null},
        {itemId: "item2", name: "Walk", photoUrl: null},
      ],
    }},
  });
  const run = (itemId) => completeLibraryPhoto({
    db, bucket: fakeBucket(), itemId, now: NOW, wait: noWait,
    generate: async () => Buffer.from("x"),
  });
  await Promise.all([run("item1"), run("item2")]);
  const {activities} = db.docs[PLAN_PATH].plan;
  assert.match(activities[0].photoUrl, /item1\.jpg|item1/);
  assert.match(activities[1].photoUrl, /item2/);
});

test("a path added while the photo is made is filled, not erased", async () => {
  const late = "users/u2/night_recoveries/e2";
  const db = fakeDb({
    "recovery_library/item1": libraryItem(),
    [PLAN_PATH]: planDoc(),
    [late]: planDoc(),
  });
  await completeLibraryPhoto({
    db, bucket: fakeBucket(), itemId: "item1", now: NOW, wait: noWait,
    generate: async () => {
      db.docs["recovery_library/item1"].pendingPlanPaths.push(late);
      return Buffer.from("x");
    },
  });
  assert.ok(db.docs[late].plan.activities[1].photoUrl);
  assert.deepEqual(db.docs["recovery_library/item1"].pendingPlanPaths, []);
});

test("a path added after the last check survives the clear", async () => {
  const late = "users/u2/night_recoveries/e2";
  const db = fakeDb({
    "recovery_library/item1": libraryItem(),
    [PLAN_PATH]: planDoc(),
  });
  const realTx = db.runTransaction;
  let calls = 0;
  db.runTransaction = (fn) => {
    calls += 1;
    // Call 1 fills the plan, call 2 clears the item: a plan registers just
    // before the clear.
    if (calls === 2) {
      db.docs["recovery_library/item1"].pendingPlanPaths.push(late);
    }
    return realTx(fn);
  };
  await completeLibraryPhoto({
    db, bucket: fakeBucket(), itemId: "item1", now: NOW, wait: noWait,
    generate: async () => Buffer.from("x"),
  });
  assert.deepEqual(db.docs["recovery_library/item1"].pendingPlanPaths, [late]);
});

test("a regeneration writes a new path and keeps the old photo URL",
    async () => {
      const oldUrl = "https://old/recovery-library%2Fitem1.jpg?token=old";
      const db = fakeDb({
        "recovery_library/item1": libraryItem({
          pendingPlanPaths: [], photoUrl: oldUrl,
        }),
      });
      const bucket = fakeBucket();
      await completeLibraryPhoto({
        db, bucket, itemId: "item1", now: NOW, wait: noWait, versioned: true,
        generate: async () => Buffer.from([1]),
      });
      assert.equal(bucket.saved.length, 1);
      assert.equal(bucket.saved[0].path, `recovery-library/item1-${NOW}.jpg`);
      const stored = db.docs["recovery_library/item1"];
      assert.notEqual(stored.photoUrl, oldUrl);
      assert.ok(stored.photoUrl.includes(`item1-${NOW}.jpg`.replace("/", "%2F")));
    });
