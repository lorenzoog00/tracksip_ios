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
  Timestamp,
  collection,
  query,
  where,
  getDocs,
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
          bucket: {file: () => ({delete: async () => {}})},
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

test("deleting an account removes every social trace of it", async () => {
  await seed();
  const deletedFiles = [];
  const bucket = {
    file: (name) => ({
      delete: async (options) => deletedFiles.push({name, options}),
    }),
  };
  const writes = {
    "public_profiles/A": {username: "a"},
    "public_profiles/B": {username: "b"},
    "usernames/a": {uid: "A"},
    "usernames/b": {uid: "B"},
    "friendships/A/friends/B": {uid: "B"},
    "friendships/B/friends/A": {uid: "A"},
    "friendships/B/friends/D": {uid: "D"},
    "friend_requests/C_A": {from: "C", to: "A"},
    "friend_requests/A_E": {from: "A", to: "E"},
    "friend_requests/C_E": {from: "C", to: "E"},
    "blocks/A/blocked/F": {uid: "F"},
    "blocks/B/blocked/A": {uid: "A"},
    "blocks/B/blocked/G": {uid: "G"},
    "shared_nights/A": {x: 1},
    "push_tokens/A": {token: "t"},
    "push_tokens/B": {token: "t"},
  };
  for (const [path, data] of Object.entries(writes)) {
    await db.doc(path).set(data);
  }
  await deleteAccount({
    db,
    auth: {deleteUser: async () => {}},
    bucket,
    uid: "A",
    authTime: Date.now() / 1000,
  });
  for (const gone of [
    "public_profiles/A", "usernames/a", "friendships/A/friends/B",
    "friendships/B/friends/A", "friend_requests/C_A", "friend_requests/A_E",
    "blocks/A/blocked/F", "blocks/B/blocked/A", "shared_nights/A",
    "push_tokens/A",
  ]) {
    assert.equal(await exists(gone), false, gone);
  }
  for (const kept of [
    "public_profiles/B", "usernames/b", "friendships/B/friends/D",
    "friend_requests/C_E", "blocks/B/blocked/G", "push_tokens/B",
  ]) {
    assert.equal(await exists(kept), true, kept);
  }
  assert.deepEqual(deletedFiles, [
    {name: "avatars/A.jpg", options: {ignoreNotFound: true}},
  ]);
});

test("a retried deletion still releases a handle whose profile is gone", async () => {
  await seed();
  await db.doc("usernames/x").set({uid: "A"});
  await db.doc("usernames/y").set({uid: "B"});
  await deleteAccount({
    db,
    auth: {deleteUser: async () => {}},
    bucket: {file: () => ({delete: async () => {}})},
    uid: "A",
    authTime: Date.now() / 1000,
  });
  assert.equal(await exists("usernames/x"), false);
  assert.equal(await exists("usernames/y"), true);
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

// social: requests, friendships, blocks
const social = require("../social");

const makeNotify = () => {
  const calls = [];
  const notify = async (...args) => {
    calls.push(args);
  };
  return {calls, notify};
};
const call = (fn, uid, data, notify) => social[fn]({db, uid, data, notify});
const exists = async (path) => (await db.doc(path).get()).exists;
const countDocs = async (path) => (await db.collection(path).get()).size;

const twoUsers = async () => {
  await claim("A", "alice");
  await claim("B", "bobby");
};

test("social: request then accept creates both friendships and notifies", async () => {
  await twoUsers();
  const {calls, notify} = makeNotify();
  assert.deepEqual(
      await call("sendFriendRequest", "A", {toUid: "B"}, notify),
      {status: "requested"},
  );
  const request = (await db.doc("friend_requests/A_B").get()).data();
  assert.equal(request.from, "A");
  assert.equal(request.to, "B");
  assert.equal(typeof request.created_at, "number");

  assert.deepEqual(
      await call("respondToFriendRequest", "B", {fromUid: "A", accept: true}, notify),
      {status: "friends"},
  );
  assert.equal(await exists("friend_requests/A_B"), false);
  assert.equal(typeof (await db.doc("friendships/A/friends/B").get()).data().since, "number");
  assert.equal(typeof (await db.doc("friendships/B/friends/A").get()).data().since, "number");
  assert.deepEqual(calls, [["B", "request", "alice"], ["A", "accepted", "bobby"]]);
});

test("social: mutual pending requests become friends with no requests left", async () => {
  await twoUsers();
  const {calls, notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  assert.deepEqual(
      await call("sendFriendRequest", "B", {toUid: "A"}, notify),
      {status: "friends"},
  );
  assert.equal(await countDocs("friend_requests"), 0);
  assert.equal(await exists("friendships/A/friends/B"), true);
  assert.equal(await exists("friendships/B/friends/A"), true);
  assert.deepEqual(calls, [["B", "request", "alice"], ["A", "accepted", "bobby"]]);
});

test("social: declining deletes the request without a friendship", async () => {
  await twoUsers();
  const {calls, notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  assert.deepEqual(
      await call("respondToFriendRequest", "B", {fromUid: "A", accept: false}, notify),
      {status: "declined"},
  );
  assert.equal(await countDocs("friend_requests"), 0);
  assert.equal(await exists("friendships/A/friends/B"), false);
  assert.equal(await exists("friendships/B/friends/A"), false);
  assert.deepEqual(calls, [["B", "request", "alice"]]);
});

test("social: responding to a missing request is not-found", async () => {
  await twoUsers();
  await assert.rejects(
      call("respondToFriendRequest", "B", {fromUid: "A", accept: true}, makeNotify().notify),
      (e) => e.code === "not-found",
  );
  assert.equal(await exists("friendships/A/friends/B"), false);
});

test("social: cancelling removes only the callers own pending request", async () => {
  await twoUsers();
  const {notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  await call("cancelFriendRequest", "B", {toUid: "A"}, notify);
  assert.equal(await exists("friend_requests/A_B"), true);
  await call("cancelFriendRequest", "A", {toUid: "B"}, notify);
  assert.equal(await exists("friend_requests/A_B"), false);
});

test("social: removing a friend deletes both sides without notifying", async () => {
  await twoUsers();
  const {calls, notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  await call("respondToFriendRequest", "B", {fromUid: "A", accept: true}, notify);
  calls.length = 0;
  await call("removeFriend", "A", {friendUid: "B"}, notify);
  assert.equal(await exists("friendships/A/friends/B"), false);
  assert.equal(await exists("friendships/B/friends/A"), false);
  assert.deepEqual(calls, []);
});

test("social: requests need usernames on both sides", async () => {
  await claim("B", "bobby");
  const {calls, notify} = makeNotify();
  await assert.rejects(
      call("sendFriendRequest", "A", {toUid: "B"}, notify),
      (e) => e.code === "failed-precondition",
  );
  await claim("A", "alice");
  await assert.rejects(
      call("sendFriendRequest", "A", {toUid: "Z"}, notify),
      (e) => e.code === "not-found",
  );
  assert.equal(await countDocs("friend_requests"), 0);
  assert.deepEqual(calls, []);
});

test("social: requesting yourself is rejected and an existing friend is a no-op", async () => {
  await twoUsers();
  const {calls, notify} = makeNotify();
  await assert.rejects(
      call("sendFriendRequest", "A", {toUid: "A"}, notify),
      (e) => e.code === "invalid-argument",
  );
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  await call("respondToFriendRequest", "B", {fromUid: "A", accept: true}, notify);
  calls.length = 0;
  assert.deepEqual(
      await call("sendFriendRequest", "A", {toUid: "B"}, notify),
      {status: "friends"},
  );
  assert.equal(await countDocs("friend_requests"), 0);
  assert.deepEqual(calls, []);
});

test("social: a failing notify does not fail the callable", async () => {
  await twoUsers();
  const notify = async () => {
    throw new Error("push down");
  };
  assert.deepEqual(
      await call("sendFriendRequest", "A", {toUid: "B"}, notify),
      {status: "requested"},
  );
  assert.equal(await exists("friend_requests/A_B"), true);
});

test("social: blocking removes friendship and requests both ways and bars requests", async () => {
  await twoUsers();
  await claim("C", "carol");
  const {notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  await call("respondToFriendRequest", "B", {fromUid: "A", accept: true}, notify);
  await call("sendFriendRequest", "A", {toUid: "C"}, notify);
  await call("sendFriendRequest", "C", {toUid: "A"}, notify);
  await db.doc("friend_requests/B_A").set({from: "B", to: "A", created_at: 1});

  await call("blockUser", "A", {targetUid: "B"}, notify);
  const block = (await db.doc("blocks/A/blocked/B").get()).data();
  assert.equal(block.uid, "B");
  assert.equal(typeof block.created_at, "number");
  assert.equal(await exists("friendships/A/friends/B"), false);
  assert.equal(await exists("friendships/B/friends/A"), false);
  assert.equal(await exists("friend_requests/B_A"), false);
  assert.equal(await exists("friendships/A/friends/C"), true);

  await assert.rejects(
      call("sendFriendRequest", "B", {toUid: "A"}, notify),
      (e) => e.code === "permission-denied",
  );
  await assert.rejects(
      call("sendFriendRequest", "A", {toUid: "B"}, notify),
      (e) => e.code === "permission-denied",
  );
  assert.equal(await exists("friend_requests/B_A"), false);

  await call("unblockUser", "A", {targetUid: "B"}, notify);
  assert.equal(await exists("blocks/A/blocked/B"), false);
  assert.deepEqual(
      await call("sendFriendRequest", "B", {toUid: "A"}, notify),
      {status: "requested"},
  );
});

test("social: blocking clears a pending request in the other direction", async () => {
  await twoUsers();
  const {notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  await call("blockUser", "A", {targetUid: "B"}, notify);
  assert.equal(await countDocs("friend_requests"), 0);
});

test("social: a block bars accepting an already-pending request", async () => {
  await twoUsers();
  const {notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  await db.doc("blocks/B/blocked/A").set({uid: "A", created_at: 1});
  await assert.rejects(
      call("respondToFriendRequest", "B", {fromUid: "A", accept: true}, notify),
      (e) => e.code === "permission-denied",
  );
  assert.equal(await exists("friendships/A/friends/B"), false);
});

test("social: responding without an explicit accept flag is rejected", async () => {
  await twoUsers();
  const {notify} = makeNotify();
  await call("sendFriendRequest", "A", {toUid: "B"}, notify);
  for (const payload of [{fromUid: "A"}, {fromUid: "A", accept: "true"}]) {
    await assert.rejects(
        call("respondToFriendRequest", "B", payload, notify),
        (e) => e.code === "invalid-argument",
    );
  }
  assert.equal(await exists("friend_requests/A_B"), true);
  assert.equal(await exists("friendships/B/friends/A"), false);
});

test("social: sending with both request docs already present ends with friends", async () => {
  await twoUsers();
  await db.doc("friend_requests/A_B").set({from: "A", to: "B", created_at: 1});
  await db.doc("friend_requests/B_A").set({from: "B", to: "A", created_at: 1});
  const {notify} = makeNotify();
  assert.deepEqual(
      await call("sendFriendRequest", "A", {toUid: "B"}, notify),
      {status: "friends"},
  );
  assert.equal(await countDocs("friend_requests"), 0);
  assert.equal(await exists("friendships/A/friends/B"), true);
  assert.equal(await exists("friendships/B/friends/A"), true);
});

// --- Friends v1: social graph and shared nights rules ----------------------
const futureTs = () => Timestamp.fromMillis(Date.now() + 3600 * 1000);
const pastTs = () => Timestamp.fromMillis(Date.now() - 60 * 1000);
const NIGHT = {
  started_at: 1, last_drink_at: 2, samples: [], drinks: [],
};
const seedFriendship = (owner, friend) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
        doc(ctx.firestore(), `friendships/${owner}/friends/${friend}`),
        {created_at: 1},
    );
  });
const seedNight = (uid, expires) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `shared_nights/${uid}`), {
      ...NIGHT, expires_at: expires,
    });
  });

test("a friend reads an unexpired shared night; expired, stranger, anon cannot", async () => {
  await seedFriendship("alice", "bob");
  await seedNight("alice", futureTs());
  const bob = env.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "shared_nights/alice")));
  const carol = env.authenticatedContext("carol").firestore();
  await assertFails(getDoc(doc(carol, "shared_nights/alice")));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "shared_nights/alice")));
  // Owner always reads.
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(getDoc(doc(alice, "shared_nights/alice")));
});

test("a friend cannot read a shared night once expires_at has passed", async () => {
  await seedFriendship("alice", "bob");
  await seedNight("alice", pastTs());
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "shared_nights/alice")));
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(getDoc(doc(alice, "shared_nights/alice")));
});

test("a friend can get a missing shared night; a stranger still cannot", async () => {
  await seedFriendship("alice", "bob");
  const bob = env.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "shared_nights/alice")));
  const carol = env.authenticatedContext("carol").firestore();
  await assertFails(getDoc(doc(carol, "shared_nights/alice")));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "shared_nights/alice")));
});

test("friendship is directional for the night read", async () => {
  // bob lists alice as a friend, but alice's doc has no bob entry.
  await seedFriendship("bob", "alice");
  await seedNight("alice", futureTs());
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "shared_nights/alice")));
});

test("owner writes a valid shared night but nothing outside the allowlist or limits", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  const ref = doc(alice, "shared_nights/alice");
  const good = {...NIGHT, ended_at: 3, expires_at: futureTs()};
  await assertSucceeds(setDoc(ref, good));
  await assertSucceeds(setDoc(ref, {...good, samples: [{t: 1, bac: 0.01}]}));
  await assertSucceeds(updateDoc(ref, {last_drink_at: 5}));
  await assertFails(setDoc(ref, {...good, notes: "secret"}));
  await assertFails(setDoc(ref, {...good, driving_mode: true}));
  await assertFails(setDoc(ref, {...good, bac_limit: 0.05}));
  await assertFails(setDoc(ref, {...good, samples: new Array(301).fill(0)}));
  await assertFails(setDoc(ref, {...good, drinks: new Array(101).fill(0)}));
  await assertFails(setDoc(ref, {...good, expires_at: Date.now() + 1000}));
  await assertFails(setDoc(ref, {...good, started_at: "x"}));
  await assertFails(setDoc(ref, {...good, ended_at: "x"}));
  // An update that smuggles a forbidden key is rejected too.
  await assertFails(updateDoc(ref, {notes: "secret"}));
  await assertSucceeds(deleteDoc(ref));
});

test("nobody else writes or deletes someone's shared night", async () => {
  await seedFriendship("alice", "bob");
  await seedNight("alice", futureTs());
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(setDoc(doc(bob, "shared_nights/alice"), {
    ...NIGHT, expires_at: futureTs(),
  }));
  await assertFails(deleteDoc(doc(bob, "shared_nights/alice")));
});

test("server-only social collections reject every client write", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  for (const path of [
    "public_profiles/alice", "usernames/alice", "friend_requests/alice_bob",
    "friendships/alice/friends/bob", "blocks/alice/blocked/bob",
    "reports/r1", "push_tokens/alice",
  ]) {
    await assertFails(setDoc(doc(alice, path), {from: "alice", to: "bob"}));
  }
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "public_profiles/alice"), {a: 1});
  });
  await assertFails(deleteDoc(doc(alice, "public_profiles/alice")));
});

test("social reads: profiles to any signed-in user, graph only to its owner or party", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    await setDoc(doc(f, "public_profiles/x"), {username: "x"});
    await setDoc(doc(f, "usernames/x"), {uid: "x"});
    await setDoc(doc(f, "friend_requests/alice_bob"), {
      from: "alice", to: "bob", created_at: 1,
    });
    await setDoc(doc(f, "friendships/alice/friends/bob"), {created_at: 1});
    await setDoc(doc(f, "blocks/alice/blocked/bob"), {created_at: 1});
    await setDoc(doc(f, "reports/r1"), {a: 1});
    await setDoc(doc(f, "push_tokens/alice"), {a: 1});
  });
  const alice = env.authenticatedContext("alice").firestore();
  const bob = env.authenticatedContext("bob").firestore();
  const carol = env.authenticatedContext("carol").firestore();
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(carol, "public_profiles/x")));
  await assertFails(getDoc(doc(anon, "public_profiles/x")));
  await assertFails(getDoc(doc(carol, "usernames/x")));
  await assertSucceeds(getDoc(doc(alice, "friend_requests/alice_bob")));
  await assertSucceeds(getDoc(doc(bob, "friend_requests/alice_bob")));
  await assertFails(getDoc(doc(carol, "friend_requests/alice_bob")));
  await assertSucceeds(getDoc(doc(alice, "friendships/alice/friends/bob")));
  await assertFails(getDoc(doc(bob, "friendships/alice/friends/bob")));
  await assertSucceeds(getDoc(doc(alice, "blocks/alice/blocked/bob")));
  await assertFails(getDoc(doc(bob, "blocks/alice/blocked/bob")));
  await assertFails(getDoc(doc(alice, "reports/r1")));
  await assertFails(getDoc(doc(alice, "push_tokens/alice")));
});

test("incognito is accepted on night events and incognito_by_default on profiles", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  await assertSucceeds(
      setDoc(doc(alice, "users/alice/night_events/a"), {...EVENT, incognito: true}),
  );
  await assertFails(
      setDoc(doc(alice, "users/alice/night_events/b"), {...EVENT, incognito: "yes"}),
  );
  await assertSucceeds(
      setDoc(doc(alice, "users/alice/profiles/alice"), {...PROFILE, incognito_by_default: true}),
  );
  await assertFails(
      setDoc(doc(alice, "users/alice/profiles/alice"), {...PROFILE, incognito_by_default: 1}),
  );
});

test("request inbox queries succeed with a party filter, unfiltered list fails", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "friend_requests/alice_bob"), {
      from: "alice", to: "bob", created_at: 1,
    });
  });
  const bob = env.authenticatedContext("bob").firestore();
  const alice = env.authenticatedContext("alice").firestore();
  const col = (c) => collection(c, "friend_requests");
  await assertSucceeds(getDocs(query(col(bob), where("to", "==", "bob"))));
  await assertSucceeds(
      getDocs(query(col(alice), where("from", "==", "alice"))),
  );
  await assertFails(getDocs(col(bob)));
  await assertFails(getDocs(query(col(bob), where("to", "==", "alice"))));
});

test("shared night expires_at is capped near 24 h", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  const at = (ms) => ({
    ...NIGHT, expires_at: Timestamp.fromMillis(Date.now() + ms),
  });
  const ref = doc(alice, "shared_nights/alice");
  await assertSucceeds(setDoc(ref, at(24 * 3600 * 1000)));
  await assertFails(setDoc(ref, at(30 * 24 * 3600 * 1000)));
});

test("friends cannot list shared_nights or read after owner tombstone", async () => {
  await seedFriendship("alice", "bob");
  await seedNight("alice", futureTs());
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDocs(collection(bob, "shared_nights")));
  await assertSucceeds(getDoc(doc(bob, "shared_nights/alice")));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "account_deletions/alice"), {a: 1});
  });
  await assertFails(getDoc(doc(bob, "shared_nights/alice")));
});

// --- Friends v1: reports, push tokens, request pushes -----------------------
const {
  reportUser,
  registerPushToken,
  notifyFromPushTokens,
} = require("../social");
const PUSH_TOKEN = "cd".repeat(32);

test("social: reportUser writes a report document", async () => {
  const logged = [];
  const original = console.error;
  console.error = (...args) => logged.push(args);
  try {
    await reportUser({db, uid: "A", data: {targetUid: "B", kind: "photo"}});
  } finally {
    console.error = original;
  }
  const snap = await db.collection("reports").get();
  assert.equal(snap.size, 1);
  const report = snap.docs[0].data();
  assert.equal(report.reporter, "A");
  assert.equal(report.target_uid, "B");
  assert.equal(report.kind, "photo");
  assert.equal(typeof report.created_at, "number");
  assert.ok(logged.some((args) => args[0] === "SOCIAL_REPORT"));
});

test("social: reportUser rejects bad kinds, self and missing targets", async () => {
  for (const data of [
    {targetUid: "B", kind: "spam"},
    {targetUid: "A", kind: "photo"},
    {kind: "photo"},
    {targetUid: "a/b", kind: "photo"},
  ]) {
    await assert.rejects(
        reportUser({db, uid: "A", data}),
        (e) => e.code === "invalid-argument",
    );
  }
  assert.equal(await countDocs("reports"), 0);
});

test("social: registerPushToken stores the token and validates it", async () => {
  await registerPushToken({
    db, uid: "A", data: {token: PUSH_TOKEN, environment: "sandbox"},
  });
  const stored = (await db.doc("push_tokens/A").get()).data();
  assert.equal(stored.token, PUSH_TOKEN);
  assert.equal(stored.environment, "sandbox");
  assert.equal(typeof stored.updated_at, "number");
  for (const data of [
    {token: "nothex", environment: "sandbox"},
    {token: PUSH_TOKEN, environment: "staging"},
  ]) {
    await assert.rejects(
        registerPushToken({db, uid: "B", data}),
        (e) => e.code === "invalid-argument",
    );
  }
  assert.equal(await exists("push_tokens/B"), false);
});

test("social: notifyFromPushTokens sends the exact copy", async () => {
  await registerPushToken({
    db, uid: "B", data: {token: PUSH_TOKEN, environment: "production"},
  });
  const sent = [];
  const notify = notifyFromPushTokens({
    db,
    send: async (environment, token, payload) => {
      sent.push({environment, token, payload});
      return {status: 200, reason: ""};
    },
  });
  await notify("B", "request", "alice");
  await notify("B", "accepted", "alice");
  assert.deepEqual(sent, [
    {
      environment: "production",
      token: PUSH_TOKEN,
      payload: {aps: {
        alert: {body: "@alice sent you a friend request"}, sound: "default",
      }},
    },
    {
      environment: "production",
      token: PUSH_TOKEN,
      payload: {aps: {
        alert: {body: "@alice accepted your friend request"}, sound: "default",
      }},
    },
  ]);
  assert.equal(await exists("push_tokens/B"), true);
});

test("social: notifyFromPushTokens does nothing without a token", async () => {
  let calls = 0;
  const notify = notifyFromPushTokens({
    db, send: async () => {
      calls++;
      return {status: 200};
    },
  });
  await notify("nobody", "request", "alice");
  assert.equal(calls, 0);
});

test("social: a 410 or BadDeviceToken removes the stored token", async () => {
  for (const result of [
    {status: 410, reason: "Unregistered"},
    {status: 400, reason: "BadDeviceToken"},
  ]) {
    await registerPushToken({
      db, uid: "B", data: {token: PUSH_TOKEN, environment: "sandbox"},
    });
    await notifyFromPushTokens({db, send: async () => result})(
        "B", "request", "alice");
    assert.equal(await exists("push_tokens/B"), false);
  }
});

test("social: other APNs failures keep the token", async () => {
  await registerPushToken({
    db, uid: "B", data: {token: PUSH_TOKEN, environment: "sandbox"},
  });
  await notifyFromPushTokens({
    db, send: async () => ({status: 429, reason: "TooManyRequests"}),
  })("B", "request", "alice");
  assert.equal(await exists("push_tokens/B"), true);
});
