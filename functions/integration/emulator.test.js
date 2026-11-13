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
const {lookupDrink} = require("../drink-lookup");
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

// The exact document shapes FirebaseManager pushes, field for field. The
// rules validate types and reject unknown keys, so if a rule edit breaks one
// of these, iOS sync breaks silently — hence they are asserted to succeed.
const EVENT = {started_at: 1, driving_mode: false, created_at: 1};
const PROFILE = {weight_kg: 70, sex: "Male", onboarding_complete: true};
const ENTRY = {
  event_id: "e1", drink_type_id: "beer", timestamp_ms: 1, quantity: 1,
};
const DRINK_TYPE = {
  name: "Beer", alcohol_percent: 5, volume_ml: 330,
  calories_per_serving: 140, is_preset: false, icon: "beer",
};
const CHALLENGE = {
  type: "dry_days", target: 5, start_date: 1,
  end_date: 2, created_at: 1, completed: false,
};

test("owner can sync ordinary data but cannot forge reports, Pro or quotas", async () => {
  const client = env.authenticatedContext("alice").firestore();
  await assertSucceeds(
      setDoc(doc(client, "users/alice/night_events/a"), EVENT),
  );
  await assertSucceeds(
      setDoc(doc(client, "users/alice/profiles/alice"), PROFILE),
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
  // A fully valid entry, so this proves the tombstone is what blocks it.
  await assertFails(
      setDoc(doc(client, "users/alice/drink_entries/a"), ENTRY),
  );
  await assertFails(deleteDoc(doc(client, "account_deletions/alice")));
});

test("every shape the iOS client pushes is accepted", async () => {
  const client = env.authenticatedContext("alice").firestore();
  for (const [path, body] of [
    ["users/alice/night_events/a", EVENT],
    ["users/alice/profiles/alice", PROFILE],
    ["users/alice/drink_entries/a", ENTRY],
    ["users/alice/drink_types/a", DRINK_TYPE],
    ["users/alice/challenges/a", CHALLENGE],
  ]) {
    await assertSucceeds(setDoc(doc(client, path), body));
  }
  // Optional fields are optional: present-and-typed also passes.
  await assertSucceeds(setDoc(doc(client, "users/alice/night_events/b"), {
    ...EVENT, name: "Friday", ended_at: 2, bac_limit: 0.05, notes: "fun",
  }));
  await assertSucceeds(setDoc(doc(client, "users/alice/profiles/alice"), {
    ...PROFILE, height_cm: 180, age: 30, country_code: "MX",
    favorite_drink_ids: ["beer"], ai_reports_enabled: true,
  }));
});

test("wrong types and unknown fields are rejected, not silently stored", async () => {
  const client = env.authenticatedContext("alice").firestore();
  for (const body of [
    {...EVENT, started_at: "yesterday"}, // number field as string
    {...EVENT, driving_mode: "yes"}, // bool field as string
    {...EVENT, notes: "x".repeat(4001)}, // past the text cap
    {...EVENT, ai_report: "forged"}, // backend-only field
    {...EVENT, extra: 1}, // unknown field
    {started_at: 1}, // required fields missing
  ]) {
    await assertFails(setDoc(doc(client, "users/alice/night_events/c"), body));
  }
  for (const body of [
    {...ENTRY, quantity: -1},
    {...ENTRY, quantity: "many"},
    {...ENTRY, comment: "x".repeat(2001)},
    {...ENTRY, event_id: 7},
  ]) {
    await assertFails(setDoc(doc(client, "users/alice/drink_entries/c"), body));
  }
  await assertFails(setDoc(doc(client, "users/alice/drink_types/c"), {
    ...DRINK_TYPE, is_preset: "no",
  }));
  await assertFails(setDoc(doc(client, "users/alice/challenges/c"), {
    ...CHALLENGE, target: "five",
  }));
  await assertFails(setDoc(doc(client, "users/alice/profiles/alice"), {
    ...PROFILE, favorite_drink_ids: "beer",
  }));
});

test("the spend ledger cannot be reset or deleted by its owner", async () => {
  await db.doc("users/alice/report_usage/current").set({total: 5});
  await db.doc("users/alice/report_jobs/j1").set({status: "done"});
  const client = env.authenticatedContext("alice").firestore();
  // Readable, so the app can show remaining free reports...
  await assertSucceeds(getDoc(doc(client, "users/alice/report_usage/current")));
  // ...but neither writable nor deletable, or the free quota resets itself.
  await assertFails(
      setDoc(doc(client, "users/alice/report_usage/current"), {total: 0}),
  );
  await assertFails(
      deleteDoc(doc(client, "users/alice/report_usage/current")),
  );
  await assertFails(deleteDoc(doc(client, "users/alice/report_jobs/j1")));
});

test("a signed-out client can reach nothing at all", async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "users/alice/night_events/a")));
  await assertFails(setDoc(doc(anon, "users/alice/night_events/a"), EVENT));
  await assertFails(getDoc(doc(anon, "account_deletions/alice")));
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

test("an old night report can be updated once with alcohol dose data", async () => {
  await seed();
  await report(async () => "TONIGHT: You logged one serving.");
  const vodka = {
    name: "Vodka", quantity: 1, volumeMlPerServing: 2000, abv: 40,
    grams: 631.2, standardDrinks: 631.2 / 14,
  };
  const upgraded = {data: {...data, payload: {
    drinks: [vodka],
    alcoholDose: {
      grams: vodka.grams, standardDrinks: vodka.standardDrinks,
      loggedServings: 1, missingServings: 0, otherGroups: 0, otherGrams: 0,
      largestEntry: vodka,
    },
  }}};
  let calls = 0;
  const generate = async () => {
    calls++;
    return "TONIGHT: Double-check the logged volume and strength.";
  };
  await Promise.all([report(generate, upgraded), report(generate, upgraded)]);
  const current = await report(generate, upgraded);
  assert.match(current.report, /^ALCOHOL LOGGED:/);
  assert.match(current.report, /45\.1 U\.S\. standard drinks/);
  assert.equal(calls, 1);
  assert.equal((await db.doc("users/alice/report_usage/current").get()).data().total, 2);
  const legacyAgain = await report(generate);
  assert.equal(legacyAgain.report, current.report);
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

// eslint-disable-next-line require-jsdoc
function lookup(overrides = {}) {
  return lookupDrink({
    db,
    uid: "alice",
    data: {query: "2 caballitos de mezcal"},
    purchase: null,
    generate: async () => JSON.stringify({
      name: "Mezcal", volumeMl: 44, abv: 42, calories: 103,
      minutes: 15, category: "agave", quantity: 2,
    }),
    ...overrides,
  });
}

test("a free account gets five drink lookups and is told what is left", async () => {
  for (let i = 0; i < 5; i++) {
    const result = await lookup();
    assert.equal(result.drink.name, "Mezcal");
    assert.equal(result.remaining, 4 - i);
  }
  await assert.rejects(lookup(), /limit/);
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).data()
          .counts.lookup,
      5,
  );
});

test("a listed tester is paid without a receipt and binds no purchase", async () => {
  // The case the allowlist exists for: a TestFlight tester has a sandbox
  // purchase that cannot be verified in production, so `purchase` is null.
  // Past the free five, and with no allowance reported back.
  for (let i = 0; i < 8; i++) {
    const result = await lookup({tester: true});
    assert.equal(result.remaining, null);
  }
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).data()
          .counts.lookup,
      8,
  );
  // No receipt means nothing to bind: a tester must not take ownership of a
  // transaction key, which is what stops two accounts sharing one purchase.
  assert.equal((await db.collection("purchase_owners").get()).empty, true);
});

test("spent lookups leave the free night report untouched", async () => {
  await seed();
  for (let i = 0; i < 5; i++) await lookup();
  const result = await report(async () => "TONIGHT: Arrange a sober ride.");
  assert.match(result.report, /sober ride/);
});

test("a failed lookup still costs the quota it reserved", async () => {
  // The reservation is committed before the model is asked, so a model that
  // answers with junk cannot be retried for free.
  await assert.rejects(
      lookup({generate: async () => "I am not JSON"}),
      /Could not read/,
  );
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).data()
          .counts.lookup,
      1,
  );
});

test("a lookup is refused while the account is being deleted", async () => {
  await db.doc("account_deletions/alice").set({requested_at: 1});
  await assert.rejects(lookup(), /deletion is in progress/);
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).exists,
      false,
  );
});

test("a purchase bound to another account cannot grant paid lookups", async () => {
  await db.doc("purchase_owners/Production-123").set({uid: "bob"});
  await assert.rejects(
      lookup({purchase: {key: "Production-123"}}),
      /another account/,
  );
  assert.equal(
      (await db.doc("users/alice/report_usage/current").get()).exists,
      false,
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

// social: usernames
const {claimUsername, searchUsers} = require("../social");

const claim = (uid, username) => claimUsername({db, uid, data: {username}});
const search = (uid, query) => searchUsers({db, uid, data: {query}});

test("social: claiming a username writes the handle and public profile", async () => {
  const result = await claim("a", "Lorenzo");
  assert.deepEqual(result, {username: "lorenzo"});
  const profile = (await db.doc("public_profiles/a").get()).data();
  assert.equal(profile.username, "lorenzo");
  assert.match(profile.avatar_color, /^#[0-9A-F]{6}$/i);
  assert.equal((await db.doc("usernames/lorenzo").get()).data().uid, "a");
});

test("social: a taken username is rejected case-insensitively", async () => {
  await claim("a", "lorenzo");
  await assert.rejects(
      claim("b", "LORENZO"),
      (e) => e.code === "already-exists" && e.message === "That username is taken.",
  );
});

test("social: disallowed usernames are rejected", async () => {
  for (const name of ["ab", "admin", "bad name", 7]) {
    await assert.rejects(
        claim("a", name),
        (e) => e.code === "invalid-argument" &&
          e.message === "That username isn't allowed.",
    );
  }
});

test("social: concurrent claims of one name produce a single owner", async () => {
  const results = await Promise.allSettled([claim("a", "same"), claim("b", "same")]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const winner = results[0].status === "fulfilled" ? "a" : "b";
  assert.equal((await db.doc("usernames/same").get()).data().uid, winner);
});

test("social: renaming frees the old name and keeps the avatar color", async () => {
  await claim("a", "lorenzo");
  const before = (await db.doc("public_profiles/a").get()).data();
  await claim("a", "newname");
  assert.equal((await db.doc("usernames/lorenzo").get()).exists, false);
  assert.equal((await db.doc("usernames/newname").get()).data().uid, "a");
  const after = (await db.doc("public_profiles/a").get()).data();
  assert.equal(after.username, "newname");
  assert.equal(after.avatar_color, before.avatar_color);
  assert.deepEqual(await claim("b", "lorenzo"), {username: "lorenzo"});
});

test("social: re-claiming your current name succeeds", async () => {
  await claim("a", "lorenzo");
  assert.deepEqual(await claim("a", "Lorenzo"), {username: "lorenzo"});
  assert.equal((await db.doc("usernames/lorenzo").get()).data().uid, "a");
});

test("social: search matches by prefix and hides blocks in both directions", async () => {
  await claim("a", "lorenzo");
  await claim("b", "lola");
  await claim("c", "other");
  const found = await search("b", "LO");
  assert.deepEqual(found.results.map((r) => r.uid), ["a"]);
  assert.equal(found.results[0].username, "lorenzo");
  assert.equal(found.results[0].photo_url, null);
  assert.ok(found.results[0].avatar_color);
  assert.deepEqual((await search("b", "l")).results, []);

  await db.doc("blocks/a/blocked/b").set({uid: "b", created_at: 1});
  assert.deepEqual((await search("b", "lo")).results, []);
  assert.deepEqual((await search("a", "lo")).results, []);

  await claim("d", "lolo");
  await db.doc("blocks/c/blocked/d").set({uid: "d", created_at: 1});
  await db.doc("blocks/c/blocked/a").set({uid: "a", created_at: 1});
  assert.deepEqual((await search("c", "lo")).results.map((r) => r.uid), ["b"]);
  assert.deepEqual((await search("d", "lo")).results.map((r) => r.uid), ["b", "a"]);
});
