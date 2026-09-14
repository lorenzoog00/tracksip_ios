const {test, before, after, beforeEach} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {execFileSync} = require("node:child_process");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  getDoc,
  deleteDoc,
  updateDoc,
} = require("firebase/firestore");
const {initializeApp, deleteApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {generateReport} = require("../report-service");
const {deleteAccount} = require("../accounts");
let env;
let app;
let db;
before(async () => {
  assert.ok(
      process.env.FIRESTORE_EMULATOR_HOST,
      "Use test:emulator, never a live project",
  );
  env = await initializeTestEnvironment({
    projectId: "demo-siptrack",
    firestore: {
      rules: process.env.SIPTRACK_RULES_BASELINE ?
        execFileSync("git", ["show", "a1bf092:firestore.rules"], {encoding: "utf8"}) :
        readFileSync("../firestore.rules", "utf8"),
    },
  });
  app = initializeApp({projectId: "demo-siptrack"});
  db = getFirestore(app);
});
after(async () => {
  await env.cleanup();
  await deleteApp(app);
});
beforeEach(async () => {
  await env.clearFirestore();
});

test("owner can sync ordinary data but cannot forge reports, Pro or quotas", async () => {
  const client = env.authenticatedContext("alice").firestore();
  await assertSucceeds(
      setDoc(doc(client, "users/alice/night_events/a"), {started_at: 1}),
  );
  await assertSucceeds(
      setDoc(doc(client, "users/alice/profiles/alice"), {weight_kg: 70}),
  );
  await assertFails(
      updateDoc(doc(client, "users/alice/night_events/a"), {
        ai_report_requested: true,
      }),
  );
  await assertFails(
      updateDoc(doc(client, "users/alice/profiles/alice"), {
        subscription_tier: "pro",
      }),
  );
  for (const path of [
    "users/alice/report_usage/current",
    "users/alice/report_jobs/a",
    "users/alice/ai_coach_reports/a",
    "users/alice/night_recoveries/a",
    "purchase_owners/a",
  ]) {
    await assertFails(setDoc(doc(client, path), {report: "forged", total: 0}));
  }
  await assertFails(getDoc(doc(client, "users/bob/night_events/a")));
  await assertFails(deleteDoc(doc(client, "users/alice")));
});

test("deletion marker blocks owner writes and cannot be removed by client", async () => {
  await db.doc("account_deletions/alice").set({startedAt: 1});
  const client = env.authenticatedContext("alice").firestore();
  await assertFails(
      setDoc(doc(client, "users/alice/drink_entries/a"), {quantity: 1}),
  );
  await assertFails(deleteDoc(doc(client, "account_deletions/alice")));
});

const data = {
  kind: "night",
  id: "night1",
  payload: {drinks: [{name: "Beer", quantity: 1}]},
};
// eslint-disable-next-line require-jsdoc
async function seed() {
  await db.doc("users/alice/night_events/night1").set({started_at: 1});
}
// eslint-disable-next-line require-jsdoc
function report(generate, overrides = {}) {
  return generateReport({
    db,
    uid: "alice",
    data,
    purchase: null,
    generate,
    ...overrides,
  });
}

test("parallel duplicate requests spend once and cached result is reused", async () => {
  await seed();
  let calls = 0;
  const generate = async () => {
    calls++;
    return "TONIGHT: Arrange a sober ride.";
  };
  await Promise.all([report(generate), report(generate), report(generate)]);
  const again = await report(generate);
  assert.match(again.report, /sober ride/);
  assert.equal(calls, 1);
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).data().total,
      1,
  );
});

test("API failure records failure and allows bounded retry", async () => {
  await seed();
  await assert.rejects(
      report(async () => {
        throw new Error("API timeout");
      }),
      /try again/,
  );
  const jobs = await db.collection("users/alice/report_jobs").get();
  assert.equal(jobs.docs[0].data().status, "failed");
  const result = await report(async () => "TONIGHT: Report recovered.");
  assert.match(result.report, /recovered/);
  assert.equal((await jobs.docs[0].ref.get()).data().attempts, 2);
});

test("deletion during generation never recreates user report or job", async () => {
  await seed();
  let authDeleted = false;
  await assert.rejects(
      report(async () => {
        await db.doc("users/alice/night_recoveries/old").set({report: "old"});
        await deleteAccount({
          db,
          auth: {
            deleteUser: async () => {
              authDeleted = true;
            },
          },
          uid: "alice",
          authTime: Date.now() / 1000,
        });
        return "Late report";
      }),
      /cancelled/,
  );
  assert.equal(authDeleted, true);
  for (const collection of [
    "night_events",
    "night_recoveries",
    "report_jobs",
    "report_usage",
  ]) {
    assert.equal(
        (await db.collection(`users/alice/${collection}`).get()).empty,
        true,
    );
  }
});

test("deletion requires recent authentication before deleting data", async () => {
  await seed();
  await assert.rejects(
      deleteAccount({db, auth: {}, uid: "alice", authTime: 1}),
      /sign in again/,
  );
  assert.equal(
      (await db.doc("users/alice/night_events/night1").get()).exists,
      true,
  );
});

test("a purchase bound to another account cannot grant paid quotas", async () => {
  await seed();
  await db.doc("purchase_owners/Production-123").set({uid: "bob"});
  await assert.rejects(
      report(async () => "Never called", {purchase: {key: "Production-123"}}),
      /another account/,
  );
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).exists,
      false,
  );
});
