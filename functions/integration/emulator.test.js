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
    "notification_prefs/A": {reactions: false},
    "notification_prefs/B": {reactions: false},
    "night_threads/A_1": {owner: "A", started_at: 1},
    "night_threads/A_1/comments/c1": {uid: "B", text: "hi"},
    "night_threads/A_1/reactions/B": {uid: "B", emoji: "beer"},
    "night_threads/B_1": {
      owner: "B", started_at: 1,
      reactions: {fire: 1, heart: 1},
      reactors: ["A", "D"],
      pushed_reactors: ["A"],
      unpushed_reactors: ["A", "D"],
      comment_count: 3,
      latest_comments: [
        {id: "c3", uid: "D", username: "dina", text: "theirs", at: 1},
        {id: "c2", uid: "A", username: "alpha", text: "mine", at: 2},
        {id: "c4", uid: "A", username: "alpha", text: "again", at: 3},
      ],
    },
    "night_threads/B_1/comments/c2":
      {uid: "A", username: "alpha", text: "mine", at: 2},
    "night_threads/B_1/comments/c3":
      {uid: "D", username: "dina", text: "theirs", at: 1},
    "night_threads/B_1/comments/c4":
      {uid: "A", username: "alpha", text: "again", at: 3},
    "night_threads/B_1/reactions/A": {uid: "A", emoji: "fire"},
    "night_threads/B_1/reactions/D": {uid: "D", emoji: "heart"},
    "night_threads/B_1/limits/A": {count: 2, last_at: 3},
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
    "push_tokens/A", "notification_prefs/A", "night_threads/A_1",
    "night_threads/A_1/comments/c1", "night_threads/A_1/reactions/B",
    "night_threads/B_1/comments/c2", "night_threads/B_1/comments/c4",
    "night_threads/B_1/reactions/A", "night_threads/B_1/limits/A",
  ]) {
    assert.equal(await exists(gone), false, gone);
  }
  // The friend's summary keeps nothing of A: not the uid, name or words.
  const friendSummary = (await db.doc("night_threads/B_1").get()).data();
  assert.deepEqual(friendSummary, {
    owner: "B", started_at: 1,
    reactions: {fire: 0, heart: 1},
    reactors: ["D"],
    pushed_reactors: [],
    unpushed_reactors: ["D"],
    comment_count: 1,
    latest_comments: [
      {id: "c3", uid: "D", username: "dina", text: "theirs", at: 1},
    ],
  });
  const flat = JSON.stringify(friendSummary);
  for (const trace of ["\"A\"", "alpha", "mine", "again"]) {
    assert.ok(!flat.includes(trace), trace);
  }
  for (const kept of [
    "public_profiles/B", "usernames/b", "friendships/B/friends/D",
    "friend_requests/C_E", "blocks/B/blocked/G", "push_tokens/B",
    "notification_prefs/B", "night_threads/B_1",
    "night_threads/B_1/comments/c3", "night_threads/B_1/reactions/D",
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
  await claim("B", "bobby");
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

test("social: reportUser rejects a target with no public profile", async () => {
  await assert.rejects(
      reportUser({db, uid: "A", data: {targetUid: "ghost", kind: "photo"}}),
      (e) => e.code === "not-found",
  );
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

test("social: registerPushToken stores the app's known features", async () => {
  const register = (features) => registerPushToken({
    db, uid: "A", data: {token: PUSH_TOKEN, environment: "sandbox", features},
  });
  const stored = async () =>
    (await db.doc("push_tokens/A").get()).data().features;
  await register(["threads"]);
  assert.deepEqual(await stored(), ["threads"]);
  // Names this backend doesn't know are dropped; repeats are kept once.
  await register(["threads", "future", "threads"]);
  assert.deepEqual(await stored(), ["threads"]);
  // An older app sends none, and re-registering clears what a newer one set.
  await register(undefined);
  assert.deepEqual(await stored(), []);
  for (const features of ["threads", [1], new Array(6).fill("threads")]) {
    await assert.rejects(register(features),
        (e) => e.code === "invalid-argument");
  }
  assert.deepEqual(await stored(), []);
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
  await notify("B", "contact", "alice");
  await notify("B", "contactNoProfile", "alice");
  const push = (body, route) => ({
    environment: "production",
    token: PUSH_TOKEN,
    payload: {
      aps: {alert: {body}, sound: "default"},
      route,
      username: "alice",
    },
  });
  assert.deepEqual(sent, [
    push("@alice sent you a friend request", "friends"),
    push("@alice accepted your friend request", "friends"),
    push("@alice is on TrackSip. Add them as a friend", "add"),
    push("@alice is on TrackSip Social. Create your profile to add them",
        "social"),
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

test("social: a token moves to the account that registered it last", async () => {
  await registerPushToken({
    db, uid: "A", data: {token: PUSH_TOKEN, environment: "sandbox"},
  });
  await registerPushToken({
    db, uid: "C", data: {token: "ef".repeat(32), environment: "sandbox"},
  });
  await registerPushToken({
    db, uid: "B", data: {token: PUSH_TOKEN, environment: "sandbox"},
  });
  assert.equal(await exists("push_tokens/A"), false);
  assert.equal((await db.doc("push_tokens/B").get()).data().token, PUSH_TOKEN);
  assert.equal(await exists("push_tokens/C"), true);
  // Re-registering your own token keeps it.
  await registerPushToken({
    db, uid: "B", data: {token: PUSH_TOKEN, environment: "sandbox"},
  });
  assert.equal(await exists("push_tokens/B"), true);
});

test("social: an account being deleted cannot claim, request, respond or register", async () => {
  await twoUsers();
  await call("sendFriendRequest", "B", {toUid: "A"}, makeNotify().notify);
  await db.doc("account_deletions/A").set({startedAt: 1});
  const deleting = (e) => e.code === "failed-precondition";
  await assert.rejects(claim("A", "another"), deleting);
  assert.equal(await exists("usernames/another"), false);
  await assert.rejects(
      call("sendFriendRequest", "A", {toUid: "B"}, makeNotify().notify),
      deleting,
  );
  await assert.rejects(
      call("respondToFriendRequest", "A", {fromUid: "B", accept: true},
          makeNotify().notify),
      deleting,
  );
  assert.equal(await exists("friendships/A/friends/B"), false);
  assert.equal(await exists("friend_requests/B_A"), true);
  await assert.rejects(
      registerPushToken({
        db, uid: "A", data: {token: PUSH_TOKEN, environment: "sandbox"},
      }),
      deleting,
  );
  assert.equal(await exists("push_tokens/A"), false);
  // A fresh account that never had a profile is also refused a username.
  await db.doc("account_deletions/Z").set({startedAt: 1});
  await assert.rejects(claim("Z", "zed"), deleting);
  assert.equal(await exists("public_profiles/Z"), false);
});

test("public_profiles can be fetched by id but not listed", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "public_profiles/x"), {username: "x"});
  });
  const carol = env.authenticatedContext("carol").firestore();
  await assertSucceeds(getDoc(doc(carol, "public_profiles/x")));
  await assertFails(getDocs(collection(carol, "public_profiles")));
  await assertFails(
      getDocs(query(collection(carol, "public_profiles"),
          where("username", "==", "x"))),
  );
});

// social: people you might know

const befriend = async (a, b) => {
  await db.doc(`friendships/${a}/friends/${b}`).set({since: 1});
  await db.doc(`friendships/${b}/friends/${a}`).set({since: 1});
};

test("social: suggestions are friends of friends, ranked by mutuals", async () => {
  for (const [uid, name] of [["A", "alice"], ["B", "bobby"], ["C", "carla"],
    ["D", "diego"], ["E", "elena"], ["F", "fabio"]]) {
    await claim(uid, name);
  }
  // A's friends: B, C. B knows D and E; C knows D. F blocked A.
  await befriend("A", "B");
  await befriend("A", "C");
  await befriend("B", "D");
  await befriend("B", "E");
  await befriend("C", "D");
  await befriend("C", "F");
  await db.doc("blocks/F/blocked/A").set({uid: "A", created_at: 1});

  const {results} = await social.suggestFriends({db, uid: "A"});
  assert.deepEqual(results.map((r) => [r.uid, r.mutual_count]),
      [["D", 2], ["E", 1]]);
  assert.equal(results[0].username, "diego");
  assert.ok(["bobby", "carla"].includes(results[0].mutual_username));
  assert.equal(results[1].mutual_username, "bobby");

  // Blocking E hides them; becoming friends with D drops them.
  await db.doc("blocks/A/blocked/E").set({uid: "E", created_at: 1});
  await befriend("A", "D");
  assert.deepEqual((await social.suggestFriends({db, uid: "A"})).results, []);
});

test("social: suggestions are empty with no friends", async () => {
  await claim("A", "alice");
  assert.deepEqual(await social.suggestFriends({db, uid: "A"}), {results: []});
});

const contactsCall = (uid, emails, {lookup, notify, now = 1000} = {}) =>
  social.matchContacts({
    db, uid, data: {emails}, now,
    lookupEmails: lookup || (async () => []),
    notify: notify || (async () => {}),
  });

test("social: contacts on Social come back; others are nudged, not shown", async () => {
  await claim("A", "alice");
  await claim("B", "bobby");
  await claim("C", "carla");
  await befriend("A", "C");
  const directory = {
    "bob@x.com": "B", "carla@x.com": "C", "dan@x.com": "D", "me@x.com": "A",
  };
  const seen = [];
  const lookup = async (emails) => {
    seen.push(...emails);
    return emails.map((e) => directory[e]).filter(Boolean);
  };
  const {calls, notify} = makeNotify();

  const {results} = await contactsCall("A",
      [" Bob@X.com ", "bob@x.com", "carla@x.com", "dan@x.com", "me@x.com",
        "not-an-email", 7],
      {lookup, notify});
  assert.deepEqual(seen, ["bob@x.com", "carla@x.com", "dan@x.com", "me@x.com"]);
  // B is on Social and not a friend; C is already a friend; D has no profile
  // and is never revealed; A is the caller.
  assert.deepEqual(results.map((r) => [r.uid, r.in_contacts]), [["B", true]]);
  assert.deepEqual(calls,
      [["B", "contact", "alice"], ["D", "contactNoProfile", "alice"]]);
  // Nothing from the contact list is stored.
  const stored = JSON.stringify(
      (await db.collection("contact_nudges").get()).docs.map((d) => d.data()));
  assert.ok(!stored.includes("@"));
});

test("social: contact pushes are at most one a day and once per sender", async () => {
  await claim("A", "alice");
  await claim("E", "erika");
  await claim("B", "bobby");
  const lookup = async () => ["B"];
  const {calls, notify} = makeNotify();
  await contactsCall("A", ["b@x.com"], {lookup, notify, now: 1000});
  await contactsCall("E", ["b@x.com"], {lookup, notify, now: 2000});
  await contactsCall("A", ["b@x.com"], {lookup, notify, now: 1000 + 2 * 86400000});
  await contactsCall("E", ["b@x.com"], {lookup, notify, now: 1000 + 2 * 86400000});
  assert.deepEqual(calls,
      [["B", "contact", "alice"], ["B", "contact", "erika"]]);
});

test("social: contact matching needs a profile and is rate limited", async () => {
  await assert.rejects(contactsCall("A", ["b@x.com"]),
      (e) => e.code === "failed-precondition");
  await claim("A", "alice");
  for (let i = 0; i < 5; i++) await contactsCall("A", ["b@x.com"]);
  await assert.rejects(contactsCall("A", ["b@x.com"]),
      (e) => e.code === "resource-exhausted");
  await contactsCall("A", ["b@x.com"], {now: 1000 + 86400000});
  await assert.rejects(contactsCall("A", "b@x.com"),
      (e) => e.code === "invalid-argument");
});

test("social: contacts hide anyone blocked in either direction", async () => {
  await claim("A", "alice");
  await claim("B", "bobby");
  await claim("C", "carla");
  await db.doc("blocks/A/blocked/B").set({uid: "B", created_at: 1});
  await db.doc("blocks/C/blocked/A").set({uid: "A", created_at: 1});
  const {calls, notify} = makeNotify();
  const {results} = await contactsCall("A", ["b@x.com", "c@x.com"],
      {lookup: async () => ["B", "C"], notify});
  assert.deepEqual(results, []);
  assert.deepEqual(calls, []);
});

// interactions: reactions
const interactions = require("../interactions");

const {Timestamp: AdminTimestamp} = require("firebase-admin/firestore");
const T = 1700000000000;
const inMs = (ms) => AdminTimestamp.fromMillis(Date.now() + ms);
// Thread docs are collected by TTL a grace period after the night expires.
const graceAfter = (night) => night.expires_at.toMillis() +
  interactions.THREAD_GRACE_MS;
const seedSharedNight = (owner = "A", overrides = {}) =>
  db.doc(`shared_nights/${owner}`).set({
    started_at: T,
    last_drink_at: T,
    samples: [],
    drinks: [],
    expires_at: inMs(3600 * 1000),
    ...overrides,
  });
const react = (uid, emoji, {notify = makeNotify().notify, now, owner = "A",
  startedAt = T} = {}) =>
  interactions.reactToNight({db, uid,
    data: {owner, startedAt, emoji}, notify, now});
const threadDoc = async () =>
  (await db.doc(`night_threads/A_${T}`).get()).data();
const reactionsSetup = async () => {
  await claim("A", "alice");
  await claim("B", "bobby");
  await befriend("A", "B");
  await seedSharedNight();
};

test("interactions: reacting sets one reaction and counts", async () => {
  await reactionsSetup();
  const night = (await db.doc("shared_nights/A").get()).data();
  assert.deepEqual(await react("B", "beer"), {emoji: "beer"});
  const thread = await threadDoc();
  assert.equal(thread.reactions.beer, 1);
  assert.deepEqual(thread.reactors, ["B"]);
  assert.equal(thread.expires_at.toMillis(), graceAfter(night));
  const mine = (await db.doc(`night_threads/A_${T}/reactions/B`).get()).data();
  assert.equal(mine.expires_at.toMillis(), graceAfter(night));
  assert.equal(mine.emoji, "beer");
  assert.equal(mine.username, "bobby");
  assert.equal(mine.uid, "B");
});

test("interactions: changing a reaction moves the count, same emoji removes", async () => {
  await reactionsSetup();
  await react("B", "beer");
  await react("B", "water");
  let thread = await threadDoc();
  assert.equal(thread.reactions.beer || 0, 0);
  assert.equal(thread.reactions.water, 1);
  assert.deepEqual(await react("B", "water"), {emoji: null});
  thread = await threadDoc();
  assert.equal(thread.reactions.water || 0, 0);
  assert.deepEqual(thread.reactors, []);
  assert.equal(await exists(`night_threads/A_${T}/reactions/B`), false);
});

test("interactions: reaction counts never go negative", async () => {
  await reactionsSetup();
  await react("B", null);
  await react("B", null);
  await react("B", "beer");
  await react("B", null);
  await react("B", null);
  const thread = await threadDoc();
  for (const count of Object.values(thread.reactions)) {
    assert.ok(count >= 0);
  }
});

test("interactions: the owner reacts to their own night without a push", async () => {
  await reactionsSetup();
  const {calls, notify} = makeNotify();
  assert.deepEqual(await react("A", "beer", {notify, now: 0}),
      {emoji: "beer"});
  const thread = await threadDoc();
  assert.equal(thread.reactions.beer, 1);
  assert.deepEqual(thread.reactors, ["A"]);
  assert.deepEqual(thread.unpushed_reactors || [], []);
  // A friend reacting later is not grouped with the owner as "1 other".
  await react("B", "water", {notify, now: 1000});
  assert.deepEqual(calls.map(([to, kind, p]) => [to, kind, p.others]),
      [["A", "reaction", 0]]);
});

test("interactions: ex-friends and blocked people cannot react", async () => {
  await reactionsSetup();
  await claim("C", "carla");
  await claim("D", "dina");
  await befriend("A", "D");
  await db.doc("blocks/A/blocked/D").set({uid: "D", created_at: 1});
  await claim("E", "elena");
  await befriend("A", "E");
  await db.doc("blocks/E/blocked/A").set({uid: "A", created_at: 1});
  const denied = (e) => e.code === "permission-denied";
  await assert.rejects(react("C", "beer"), denied);
  await assert.rejects(react("D", "beer"), denied);
  await assert.rejects(react("E", "beer"), denied);
  await assert.rejects(react("B", "pizza"),
      (e) => e.code === "invalid-argument");
  // Only a beer or a water.
  await assert.rejects(react("B", "fire"),
      (e) => e.code === "invalid-argument");
});

test("interactions: stale or expired nights are not found", async () => {
  await reactionsSetup();
  const notFound = (e) => e.code === "not-found";
  await assert.rejects(react("B", "beer", {startedAt: T + 1}), notFound);
  await seedSharedNight("A", {expires_at: inMs(-60 * 1000)});
  await assert.rejects(react("B", "beer"), notFound);
  await assert.rejects(react("B", "beer", {owner: "Z"}), notFound);
});

test("interactions: reacting needs a username", async () => {
  await reactionsSetup();
  await db.doc("friendships/A/friends/X").set({since: 1});
  await assert.rejects(react("X", "beer"),
      (e) => e.code === "failed-precondition");
});

test("interactions: reaction pushes are grouped", async () => {
  await reactionsSetup();
  await claim("C", "carla");
  await claim("D", "dina");
  await befriend("A", "C");
  await befriend("A", "D");
  const {calls, notify} = makeNotify();
  const minute = 60 * 1000;
  await react("B", "beer", {notify, now: 0});
  assert.deepEqual(calls, [["A", "reaction", {
    from: "bobby", owner: "A", ownerName: "alice", startedAt: T,
    emoji: "🍻", others: 0,
  }]]);
  await react("C", "water", {notify, now: minute});
  assert.equal(calls.length, 1);
  await react("D", "beer", {notify, now: 16 * minute});
  assert.equal(calls.length, 2);
  assert.equal(calls[1][2].from, "dina");
  assert.equal(calls[1][2].others, 1);
  await react("B", "water", {notify, now: 40 * minute});
  assert.equal(calls.length, 2);
});

test("interactions: a failing push does not undo the reaction", async () => {
  await reactionsSetup();
  const original = console.error;
  console.error = () => {};
  try {
    const notify = async () => {
      throw new Error("push down");
    };
    assert.deepEqual(await react("B", "beer", {notify}), {emoji: "beer"});
  } finally {
    console.error = original;
  }
  assert.equal((await threadDoc()).reactions.beer, 1);
});

test("interactions: others never counts the pusher or removed reactions", async () => {
  await reactionsSetup();
  await claim("C", "carla");
  await claim("D", "dina");
  await befriend("A", "C");
  await befriend("A", "D");
  const minute = 60 * 1000;
  const first = makeNotify();
  await react("B", "beer", {notify: first.notify, now: 0});
  await react("C", "water", {notify: first.notify, now: minute});
  await react("C", "beer", {notify: first.notify, now: 20 * minute});
  assert.equal(first.calls.length, 2);
  assert.equal(first.calls[1][2].from, "carla");
  assert.equal(first.calls[1][2].others, 0);

  await db.recursiveDelete(db.collection("night_threads"));
  const second = makeNotify();
  await react("B", "beer", {notify: second.notify, now: 0});
  await react("C", "water", {notify: second.notify, now: minute});
  await react("C", "water", {notify: second.notify, now: 2 * minute});
  await react("D", "water", {notify: second.notify, now: 20 * minute});
  assert.equal(second.calls.length, 2);
  assert.equal(second.calls[1][2].from, "dina");
  assert.equal(second.calls[1][2].others, 0);
});

// interactions: comments
const comment = (uid, text, {notify = makeNotify().notify, now = 1000000,
  owner = "A", startedAt = T} = {}) =>
  interactions.addComment({db, uid,
    data: {owner, startedAt, text}, notify, now});
const uncomment = (uid, commentId, {owner = "A", startedAt = T} = {}) =>
  interactions.deleteComment({db, uid,
    data: {owner, startedAt, commentId}});
const thread = (uid, {owner = "A", startedAt = T} = {}) =>
  interactions.getNightThread({db, uid, data: {owner, startedAt}});
const commentsSetup = async () => {
  await reactionsSetup();
  await claim("C", "carla");
  await befriend("A", "C");
};
const invalid = (message) => (e) =>
  e.code === "invalid-argument" && e.message === message;

test("interactions: adding a comment trims the text and updates the summary", async () => {
  await commentsSetup();
  const night = (await db.doc("shared_nights/A").get()).data();
  const result = await comment("B", "  hola  ");
  assert.equal(result.text, "hola");
  assert.deepEqual(result.mentions, []);
  assert.equal(result.at, 1000000);
  const summary = await threadDoc();
  assert.equal(summary.comment_count, 1);
  assert.equal(summary.latest_comments[0].text, "hola");
  assert.equal(summary.latest_comments[0].id, result.id);
  assert.equal(summary.expires_at.toMillis(), graceAfter(night));
  const stored = (await db.doc(
      `night_threads/A_${T}/comments/${result.id}`).get()).data();
  assert.equal(stored.uid, "B");
  assert.equal(stored.username, "bobby");
  assert.equal(stored.expires_at.toMillis(), graceAfter(night));
  const limit = (await db.doc(`night_threads/A_${T}/limits/B`).get()).data();
  assert.equal(limit.expires_at.toMillis(), graceAfter(night));
});

test("interactions: comments keep the reaction fields on the summary", async () => {
  await commentsSetup();
  await react("B", "beer");
  await comment("C", "nice");
  const summary = await threadDoc();
  assert.equal(summary.reactions.beer, 1);
  assert.deepEqual(summary.reactors, ["B"]);
  assert.equal(summary.comment_count, 1);
  await react("C", "water");
  assert.equal((await threadDoc()).comment_count, 1);
  assert.equal((await threadDoc()).latest_comments.length, 1);
});

test("interactions: empty, long and link comments are rejected", async () => {
  await commentsSetup();
  await assert.rejects(comment("B", "   "),
      invalid("Write a comment first."));
  await assert.rejects(comment("B", null),
      invalid("Write a comment first."));
  await assert.rejects(comment("B", "x".repeat(201)),
      invalid("Comments are 200 characters at most."));
  await comment("B", "x".repeat(200));
  for (const text of ["see https://x.io", "go to www.foo"]) {
    await assert.rejects(comment("C", text, {now: 5000000}),
        invalid("Links aren't allowed in comments."));
  }
});

test("interactions: ordinary chat with dots is not mistaken for a link", async () => {
  await commentsSetup();
  let now = 0;
  for (const text of ["jaja.Me voy", "genial.Co", "ya.us", "ya pide agua.jaja",
    "foo.com now"]) {
    now += 5000;
    assert.equal((await comment("B", text, {now})).text, text);
  }
});

test("interactions: comments are rate limited per person per night", async () => {
  await commentsSetup();
  await comment("B", "one", {now: 0});
  await assert.rejects(comment("B", "two", {now: 1000}),
      (e) => e.code === "resource-exhausted" &&
          e.message === "Slow down a little.");
  await comment("B", "two", {now: 3000});
  await comment("C", "other person", {now: 3500});
  for (let i = 2; i < 50; i++) await comment("B", `c${i}`, {now: i * 3000});
  await assert.rejects(comment("B", "again", {now: 50 * 3000}),
      (e) => e.code === "resource-exhausted" &&
          e.message === "That's the comment limit for this night.");
});

test("interactions: owner may comment, ex-friends and blocked people may not", async () => {
  await commentsSetup();
  await comment("A", "my night");
  await claim("X", "xavier");
  await assert.rejects(comment("X", "hi"),
      (e) => e.code === "permission-denied");
  await db.doc("blocks/A/blocked/C").set({uid: "C", created_at: 1});
  await assert.rejects(comment("C", "hi"),
      (e) => e.code === "permission-denied");
  await assert.rejects(comment("B", "hi", {startedAt: T + 1}),
      (e) => e.code === "not-found");
});

test("interactions: comment pushes go to the owner and earlier commenters", async () => {
  await commentsSetup();
  const {calls, notify} = makeNotify();
  const payload = (from, text) => ({
    from, owner: "A", ownerName: "alice", startedAt: T, text,
  });
  await comment("B", "first", {notify, now: 0});
  assert.deepEqual(calls, [["A", "comment", payload("bobby", "first")]]);
  calls.length = 0;
  // Recipients are pushed in parallel, so calls arrive in any order.
  const byRecipient = (list) =>
    [...list].sort((a, b) => a[0].localeCompare(b[0]));
  await comment("C", "second", {notify, now: 5000});
  assert.deepEqual(byRecipient(calls), [
    ["A", "comment", payload("carla", "second")],
    ["B", "reply", payload("carla", "second")],
  ]);
  calls.length = 0;
  await comment("A", "third", {notify, now: 10000});
  assert.deepEqual(byRecipient(calls), [
    ["B", "reply", payload("alice", "third")],
    ["C", "reply", payload("alice", "third")],
  ]);
  calls.length = 0;
  await comment("B", "fourth", {notify, now: 15000});
  assert.deepEqual(byRecipient(calls).map((c) => [c[0], c[1]]),
      [["A", "comment"], ["C", "reply"]]);
});

test("interactions: mentions are deduped and limited to viewers", async () => {
  await commentsSetup();
  await claim("Z", "zed");
  const {calls, notify} = makeNotify();
  await comment("B", "earlier", {notify, now: 0});
  calls.length = 0;
  const result = await comment("C", "@bobby @bobby @zed @carla hey",
      {notify, now: 5000});
  assert.deepEqual(result.mentions, [{uid: "B", username: "bobby"}]);
  // Recipients are pushed in parallel, so sort before comparing.
  assert.deepEqual(
      [...calls].sort((a, b) => a[0].localeCompare(b[0]))
          .map((c) => [c[0], c[1]]),
      [["A", "comment"], ["B", "mention"]]);
  const stored = (await db.doc(
      `night_threads/A_${T}/comments/${result.id}`).get()).data();
  assert.deepEqual(stored.mentions, [{uid: "B", username: "bobby"}]);
});

test("interactions: a mention followed by punctuation still resolves", async () => {
  await commentsSetup();
  const {calls, notify} = makeNotify();
  const result = await comment("C", "thanks @bobby. and @alice_ too",
      {notify, now: 0});
  assert.deepEqual(result.mentions, [
    {uid: "B", username: "bobby"},
    {uid: "A", username: "alice"},
  ]);
  assert.deepEqual(
      [...calls].sort((a, b) => a[0].localeCompare(b[0]))
          .map((c) => [c[0], c[1]]),
      [["A", "comment"], ["B", "mention"]]);
  // A name that only exists with the trailing dot stripped below three
  // characters, or not at all, is still nobody.
  const none = await comment("C", "hi @bo. and @nobody_", {now: 5000});
  assert.deepEqual(none.mentions, []);
});

test("interactions: mentioning the owner still sends the owner a comment push", async () => {
  await commentsSetup();
  const {calls, notify} = makeNotify();
  await comment("B", "hey @alice", {notify, now: 0});
  assert.deepEqual(calls.map((c) => [c[0], c[1]]), [["A", "comment"]]);
});

test("interactions: pushes skip ex-friends and blocked people", async () => {
  await commentsSetup();
  const {calls, notify} = makeNotify();
  await comment("B", "earlier", {notify, now: 0});
  await comment("C", "earlier too", {notify, now: 5000});
  calls.length = 0;
  await db.doc("friendships/A/friends/B").delete();
  await db.doc("blocks/C/blocked/A").set({uid: "A", created_at: 1});
  await comment("A", "later", {notify, now: 10000});
  assert.deepEqual(calls, []);
});

test("interactions: a failing comment push does not undo the comment", async () => {
  await commentsSetup();
  const original = console.error;
  console.error = () => {};
  try {
    const notify = async () => {
      throw new Error("push down");
    };
    const result = await comment("B", "still here", {notify});
    assert.equal(result.text, "still here");
  } finally {
    console.error = original;
  }
  assert.equal((await threadDoc()).comment_count, 1);
});

test("interactions: authors and the owner delete comments, others cannot", async () => {
  await commentsSetup();
  const first = await comment("B", "one", {now: 0});
  const second = await comment("C", "two", {now: 5000});
  const third = await comment("B", "three", {now: 10000});
  const fourth = await comment("C", "four", {now: 15000});
  await claim("D", "dina");
  await befriend("A", "D");
  await assert.rejects(uncomment("D", first.id),
      (e) => e.code === "permission-denied");
  await assert.rejects(uncomment("B", second.id),
      (e) => e.code === "permission-denied");
  assert.deepEqual(await uncomment("B", first.id), {status: "deleted"});
  let summary = await threadDoc();
  assert.equal(summary.comment_count, 3);
  assert.deepEqual(summary.latest_comments.map((c) => c.id),
      [second.id, third.id, fourth.id]);
  assert.deepEqual(await uncomment("A", fourth.id), {status: "deleted"});
  summary = await threadDoc();
  assert.equal(summary.comment_count, 2);
  assert.deepEqual(summary.latest_comments.map((c) => c.id),
      [second.id, third.id]);
  assert.equal(await exists(`night_threads/A_${T}/comments/${fourth.id}`),
      false);
  await assert.rejects(uncomment("A", fourth.id),
      (e) => e.code === "not-found");
  await uncomment("A", second.id);
  await uncomment("A", third.id);
  summary = await threadDoc();
  assert.equal(summary.comment_count, 0);
  assert.deepEqual(summary.latest_comments, []);
});

test("interactions: the thread is oldest first and hides blocks both ways", async () => {
  await commentsSetup();
  await claim("D", "dina");
  await befriend("A", "D");
  await db.doc("blocks/D/blocked/C").set({uid: "C", created_at: 1});
  await comment("B", "b1", {now: 0});
  await comment("C", "c1", {now: 5000});
  await comment("D", "d1", {now: 10000});
  await react("B", "beer", {now: 1});
  await react("C", "water", {now: 2});
  await react("D", "water", {now: 3});

  const mine = await thread("B");
  assert.deepEqual(mine.comments.map((c) => c.text), ["b1", "c1", "d1"]);
  assert.deepEqual(mine.reactions.map((r) => r.emoji),
      ["beer", "water", "water"]);
  assert.deepEqual(Object.keys(mine.comments[0]).sort(),
      ["at", "id", "mentions", "text", "uid", "username"]);
  assert.deepEqual(Object.keys(mine.reactions[0]).sort(),
      ["at", "emoji", "uid", "username"]);

  const dinas = await thread("D");
  assert.deepEqual(dinas.comments.map((c) => c.text), ["b1", "d1"]);
  assert.deepEqual(dinas.reactions.map((r) => r.uid), ["B", "D"]);
  const carlas = await thread("C");
  assert.deepEqual(carlas.comments.map((c) => c.text), ["b1", "c1"]);
  assert.deepEqual(carlas.reactions.map((r) => r.uid), ["B", "C"]);

  await claim("X", "xavier");
  await assert.rejects(thread("X"), (e) => e.code === "permission-denied");
});

test("interactions: a thread outlives the expiry it was first written with", async () => {
  await commentsSetup();
  const hour = 3600 * 1000;
  await react("B", "beer");
  const first = await comment("B", "early", {now: Date.now()});
  // The night goes on: every drink pushes its expiry later.
  await seedSharedNight("A", {expires_at: inMs(30 * hour)});
  const night = (await db.doc("shared_nights/A").get()).data();
  // Past the expiry the first writes copied, the night is still live.
  const later = Date.now() + 2 * hour;
  await react("C", "water", {now: later});
  const second = await comment("C", "later", {now: later});
  let summary = await threadDoc();
  assert.deepEqual(summary.reactions, {beer: 1, water: 1});
  assert.equal(summary.comment_count, 2);
  assert.equal(summary.expires_at.toMillis(), graceAfter(night));
  // Re-tapping a reaction made before the move toggles it, never counts it
  // twice.
  assert.deepEqual(await react("B", "beer", {now: later}), {emoji: null});
  summary = await threadDoc();
  assert.deepEqual(summary.reactions, {beer: 0, water: 1});
  const read = await interactions.getNightThread({db, uid: "B",
    data: {owner: "A", startedAt: T}, now: later});
  assert.deepEqual(read.comments.map((c) => c.id), [first.id, second.id]);
});

// interactions: reporting a comment
const reportComment = (uid, data) => reportUser({db, uid,
  data: {kind: "comment", owner: "A", startedAt: T, ...data}});

test("interactions: reporting a comment stores a copy of it", async () => {
  await commentsSetup();
  const said = await comment("C", "something rude", {now: 0});
  const logged = [];
  const original = console.error;
  console.error = (...args) => logged.push(args);
  try {
    assert.deepEqual(
        await reportComment("B", {targetUid: "C", commentId: said.id}),
        {status: "reported"});
  } finally {
    console.error = original;
  }
  const reports = await db.collection("reports").get();
  assert.equal(reports.size, 1);
  const report = reports.docs[0].data();
  assert.equal(report.reporter, "B");
  assert.equal(report.target_uid, "C");
  assert.equal(report.kind, "comment");
  const copy = {
    id: said.id, night: `A_${T}`, uid: "C", username: "carla",
    text: "something rude",
  };
  assert.deepEqual(report.comment, copy);
  const line = logged.find((args) => args[0] === "SOCIAL_REPORT");
  assert.deepEqual(line[1].comment, copy);
  // The owner may report a comment on their own night too.
  await reportComment("A", {targetUid: "C", commentId: said.id});
  assert.equal(await countDocs("reports"), 2);
});

test("interactions: a comment report must match a visible comment", async () => {
  await commentsSetup();
  const said = await comment("C", "hey", {now: 0});
  const fails = (uid, data, code) =>
    assert.rejects(reportComment(uid, data), (e) => e.code === code);
  // Not that person's comment, or no such comment.
  await fails("B", {targetUid: "A", commentId: said.id}, "not-found");
  await fails("B", {targetUid: "C", commentId: "nope"}, "not-found");
  // Bad references.
  await fails("B", {targetUid: "C", commentId: "a/b"}, "invalid-argument");
  await fails("B", {targetUid: "C"}, "invalid-argument");
  await fails("B", {targetUid: "C", commentId: said.id, startedAt: "x"},
      "invalid-argument");
  // Someone who can't see the night, or a night that is gone.
  await claim("X", "xavier");
  await fails("X", {targetUid: "C", commentId: said.id}, "permission-denied");
  await fails("B", {targetUid: "C", commentId: said.id, startedAt: T + 1},
      "not-found");
  await seedSharedNight("A", {expires_at: inMs(-60 * 1000)});
  await fails("B", {targetUid: "C", commentId: said.id}, "not-found");
  assert.equal(await countDocs("reports"), 0);
});

// interactions: thread pushes and notification prefs
const threadPushes = (result = {status: 200, reason: ""}) => {
  const sent = [];
  const notify = interactions.notifyThread({
    db,
    send: async (environment, token, payload) => {
      sent.push({environment, token, payload});
      return result;
    },
  });
  return {sent, notify};
};
const tokenForA = () => registerPushToken({db, uid: "A",
  data: {token: PUSH_TOKEN, environment: "production", features: ["threads"]}});
const ON_OLIVES = {from: "bobby", owner: "O", ownerName: "olive", startedAt: T};

test("interactions: notifyThread copy and route", async () => {
  await tokenForA();
  const {sent, notify} = threadPushes();
  await notify("A", "reaction", {...ON_OLIVES, emoji: "🍻", others: 0});
  await notify("A", "reaction", {...ON_OLIVES, emoji: "🍻", others: 1});
  await notify("A", "reaction", {...ON_OLIVES, emoji: "🔥", others: 4});
  await notify("A", "comment", {...ON_OLIVES, text: "nice one"});
  await notify("A", "reply", {...ON_OLIVES, text: "same"});
  await notify("A", "reply", {...ON_OLIVES, from: "olive", text: "thanks"});
  await notify("A", "mention", {...ON_OLIVES, text: "@alice look"});
  await notify("A", "comment", {...ON_OLIVES, text: "y".repeat(80)});
  await notify("A", "comment", {...ON_OLIVES, text: "x".repeat(81)});
  await notify("A", "comment", {...ON_OLIVES, text: "🍻".repeat(81)});
  const push = (body) => ({
    environment: "production",
    token: PUSH_TOKEN,
    payload: {
      aps: {"alert": {body}, "sound": "default", "thread-id": `O_${T}`},
      route: "thread",
      owner: "O",
      started_at: T,
    },
  });
  assert.deepEqual(sent, [
    push("@bobby reacted 🍻 to your night"),
    push("@bobby and 1 other reacted to your night"),
    push("@bobby and 4 others reacted to your night"),
    push("@bobby commented: nice one"),
    push("@bobby on @olive's night: same"),
    push("@olive replied on their night: thanks"),
    push("@bobby mentioned you on @olive's night: @alice look"),
    push(`@bobby commented: ${"y".repeat(80)}`),
    push(`@bobby commented: ${"x".repeat(79)}…`),
    push(`@bobby commented: ${"🍻".repeat(79)}…`),
  ]);
  await assert.rejects(notify("A", "poke", ON_OLIVES), /unknown/);
});

test("interactions: notifyThread does nothing without a token", async () => {
  const {sent, notify} = threadPushes();
  await notify("A", "comment", {...ON_OLIVES, text: "hi"});
  assert.deepEqual(sent, []);
});

test("interactions: an app without the threads feature gets no thread push", async () => {
  const every = [
    ["reaction", {...ON_OLIVES, emoji: "🍻", others: 0}],
    ["comment", {...ON_OLIVES, text: "hi"}],
    ["reply", {...ON_OLIVES, text: "hi"}],
    ["mention", {...ON_OLIVES, text: "hi"}],
  ];
  // An older app sends no features at all.
  for (const data of [{}, {features: []}]) {
    await registerPushToken({db, uid: "A",
      data: {token: PUSH_TOKEN, environment: "production", ...data}});
    const {sent, notify} = threadPushes();
    for (const [kind, payload] of every) await notify("A", kind, payload);
    assert.deepEqual(sent, []);
    // Friend-request pushes still reach it.
    const requests = [];
    await notifyFromPushTokens({
      db, send: async (environment, token, payload) => {
        requests.push(payload.route);
        return {status: 200, reason: ""};
      },
    })("A", "request", "bobby");
    assert.deepEqual(requests, ["friends"]);
  }
});

test("interactions: a dead token is removed by a thread push", async () => {
  await tokenForA();
  const {notify} = threadPushes({status: 410, reason: "Unregistered"});
  await notify("A", "comment", {...ON_OLIVES, text: "hi"});
  assert.equal(await exists("push_tokens/A"), false);
});

test("interactions: prefs off skips the push", async () => {
  await tokenForA();
  const every = [
    ["reaction", {...ON_OLIVES, emoji: "🍻", others: 0}],
    ["comment", {...ON_OLIVES, text: "hi"}],
    ["reply", {...ON_OLIVES, text: "hi"}],
    ["mention", {...ON_OLIVES, text: "hi"}],
  ];
  const kindsSent = async () => {
    const {sent, notify} = threadPushes();
    const kinds = [];
    for (const [kind, payload] of every) {
      const before = sent.length;
      await notify("A", kind, payload);
      if (sent.length > before) kinds.push(kind);
    }
    return kinds;
  };

  // Missing doc, missing keys and explicit true all mean on.
  assert.deepEqual(await kindsSent(), every.map(([kind]) => kind));
  await db.doc("notification_prefs/A").set({});
  assert.deepEqual(await kindsSent(), every.map(([kind]) => kind));
  await db.doc("notification_prefs/A")
      .set({reactions: true, comments: true, replies: true});
  assert.deepEqual(await kindsSent(), every.map(([kind]) => kind));

  await db.doc("notification_prefs/A").set({reactions: false});
  assert.deepEqual(await kindsSent(), ["comment", "reply", "mention"]);
  await db.doc("notification_prefs/A").set({comments: false});
  assert.deepEqual(await kindsSent(), ["reaction", "reply", "mention"]);
  // Mentions obey the replies switch.
  await db.doc("notification_prefs/A").set({replies: false});
  assert.deepEqual(await kindsSent(), ["reaction", "comment"]);
  await db.doc("notification_prefs/A")
      .set({reactions: false, comments: false, replies: false});
  assert.deepEqual(await kindsSent(), []);
});

// interactions: cleanup when a shared night is deleted
test("interactions: deleteThreadsFor removes the owner's threads whole", async () => {
  await commentsSetup();
  await react("B", "beer");
  await comment("C", "hi");
  await db.doc("night_threads/A_5").set({owner: "A", started_at: 5});
  await db.doc("night_threads/A_5/comments/old").set({uid: "B"});
  await db.doc(`night_threads/C_${T}`).set({owner: "C", started_at: T});
  await db.doc(`night_threads/C_${T}/comments/x`).set({uid: "A"});
  await db.doc(`night_threads/C_${T}/reactions/A`).set({uid: "A"});
  assert.equal(await countDocs(`night_threads/A_${T}/limits`), 1);

  await interactions.deleteThreadsFor({db, uid: "A"});

  for (const gone of [`night_threads/A_${T}`, "night_threads/A_5"]) {
    assert.equal(await exists(gone), false, gone);
    for (const sub of ["reactions", "comments", "limits"]) {
      assert.equal(await countDocs(`${gone}/${sub}`), 0, `${gone}/${sub}`);
    }
  }
  // Someone else's night, even one A took part in, is untouched.
  for (const kept of [`night_threads/C_${T}`,
    `night_threads/C_${T}/comments/x`, `night_threads/C_${T}/reactions/A`]) {
    assert.equal(await exists(kept), true, kept);
  }
});

test("interactions: deleteThreadsFor with no threads is a no-op", async () => {
  await interactions.deleteThreadsFor({db, uid: "nobody"});
});

// --- Night threads and notification prefs rules ----------------------------
// Thread docs carry a TTL-only expires_at; visibility follows the shared
// night (NIGHT.started_at is 1, so alice's thread key is alice_1).
const seedThread = (owner, expires = futureTs()) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    const fs = ctx.firestore();
    const key = `night_threads/${owner}_1`;
    await setDoc(doc(fs, key), {
      owner, started_at: 1, expires_at: expires, reactions: {beer: 2},
      comment_count: 1,
    });
    await setDoc(doc(fs, `${key}/comments/c1`),
        {uid: "bob", text: "hi", expires_at: expires});
    for (const uid of ["bob", "erin"]) {
      await setDoc(doc(fs, `${key}/reactions/${uid}`),
          {uid, emoji: "beer", expires_at: expires});
    }
    await setDoc(doc(fs, `${key}/limits/bob`), {count: 1, last_at: 1});
  });

test("thread rules: owner and friends get the summary and their own reaction", async () => {
  await seedFriendship("alice", "bob");
  await seedFriendship("alice", "erin");
  await seedFriendship("alice", "dave");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), "friendships/alice/friends/dave"));
  });
  await seedFriendship("carol", "alice");
  await seedNight("alice", futureTs());
  await seedThread("alice");
  const key = "night_threads/alice_1";

  for (const uid of ["alice", "bob", "erin"]) {
    const fs = env.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(fs, key)));
    // Comments only come through getNightThread, which filters blocks.
    await assertFails(getDocs(collection(fs, `${key}/comments`)));
    await assertFails(getDoc(doc(fs, `${key}/comments/c1`)));
    await assertFails(getDocs(collection(fs, `${key}/reactions`)));
    await assertFails(getDoc(doc(fs, `${key}/limits/bob`)));
    await assertFails(getDocs(collection(fs, `${key}/limits`)));
  }
  // Each person reads only their own reaction doc, even the owner.
  const bob = env.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, `${key}/reactions/bob`)));
  await assertFails(getDoc(doc(bob, `${key}/reactions/erin`)));
  const erin = env.authenticatedContext("erin").firestore();
  await assertSucceeds(getDoc(doc(erin, `${key}/reactions/erin`)));
  await assertFails(getDoc(doc(erin, `${key}/reactions/bob`)));
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(getDoc(doc(alice, `${key}/reactions/bob`)));
  // A missing reaction doc is readable, so the listener survives "none".
  await assertSucceeds(getDoc(doc(alice, `${key}/reactions/alice`)));

  // carol is a stranger to alice (friendship is directional), dave an
  // ex-friend.
  for (const [uid, fs] of [
    ["carol", env.authenticatedContext("carol").firestore()],
    ["dave", env.authenticatedContext("dave").firestore()],
    ["anon", env.unauthenticatedContext().firestore()],
  ]) {
    await assertFails(getDoc(doc(fs, key)));
    await assertFails(getDoc(doc(fs, `${key}/reactions/${uid}`)));
    await assertFails(getDocs(collection(fs, `${key}/comments`)));
    await assertFails(getDoc(doc(fs, `${key}/comments/c1`)));
  }
  // No listing threads, even for the owner.
  await assertFails(getDocs(collection(alice, "night_threads")));
});

test("thread rules: visibility follows the shared night, not the thread copy", async () => {
  await seedFriendship("alice", "bob");
  await seedNight("alice", futureTs());
  // The thread's own expires_at is long past (an old copy TTL hasn't
  // collected yet): it means nothing while the night is live.
  await seedThread("alice", pastTs());
  const key = "night_threads/alice_1";
  for (const uid of ["alice", "bob"]) {
    const fs = env.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(fs, key)));
    await assertSucceeds(getDoc(doc(fs, `${key}/reactions/${uid}`)));
  }
  // A night nobody has reacted to yet has no summary; the feed card's
  // listener must not die on it.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), key));
  });
  for (const uid of ["alice", "bob"]) {
    const fs = env.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(fs, key)));
  }
  const carol = env.authenticatedContext("carol").firestore();
  await assertFails(getDoc(doc(carol, key)));
});

test("thread rules: an expired, replaced or deleted night hides its thread", async () => {
  await seedFriendship("alice", "bob");
  await seedThread("alice");
  const key = "night_threads/alice_1";
  const hidden = async () => {
    for (const uid of ["alice", "bob"]) {
      const fs = env.authenticatedContext(uid).firestore();
      await assertFails(getDoc(doc(fs, key)));
      await assertFails(getDoc(doc(fs, `${key}/reactions/${uid}`)));
    }
  };
  // Expired, though the thread docs themselves are still live.
  await seedNight("alice", pastTs());
  await hidden();
  // A new night replaced it: its started_at no longer matches the key.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "shared_nights/alice"),
        {...NIGHT, started_at: 2, expires_at: futureTs()});
  });
  await hidden();
  // The night was deleted (incognito, deleted night or account).
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), "shared_nights/alice"));
  });
  await hidden();
  // A malformed key never matches a night.
  await seedNight("alice", futureTs());
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "night_threads/alice")));
  await assertFails(getDoc(doc(bob, "night_threads/alice_x")));
});

test("thread rules: nobody writes a thread from a client", async () => {
  await seedFriendship("alice", "bob");
  await seedThread("alice", futureTs());
  const key = "night_threads/alice_1";
  for (const uid of ["alice", "bob"]) {
    const fs = env.authenticatedContext(uid).firestore();
    await assertFails(setDoc(doc(fs, key), {owner: "alice", started_at: 1}));
    await assertFails(updateDoc(doc(fs, key), {comment_count: 9}));
    await assertFails(deleteDoc(doc(fs, key)));
    await assertFails(setDoc(doc(fs, `${key}/comments/c9`),
        {uid, text: "forged"}));
    await assertFails(deleteDoc(doc(fs, `${key}/comments/c1`)));
    await assertFails(setDoc(doc(fs, `${key}/reactions/${uid}`),
        {uid, emoji: "fire"}));
    await assertFails(setDoc(doc(fs, `${key}/limits/${uid}`), {count: 0}));
    await assertFails(setDoc(doc(fs, `night_threads/${uid}_3`),
        {owner: uid, started_at: 3}));
  }
});

test("prefs rules: the owner reads and writes only the three switches", async () => {
  const alice = env.authenticatedContext("alice").firestore();
  const ref = doc(alice, "notification_prefs/alice");
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(setDoc(ref, {reactions: false}));
  await assertSucceeds(setDoc(ref,
      {reactions: true, comments: false, replies: true}));
  await assertSucceeds(updateDoc(ref, {replies: false}));
  await assertSucceeds(getDoc(ref));
  await assertFails(setDoc(ref, {reactions: "off"}));
  await assertFails(setDoc(ref, {replies: 0}));
  await assertFails(setDoc(ref, {reactions: true, mentions: false}));
  await assertFails(updateDoc(ref, {extra: true}));
  await assertFails(setDoc(doc(alice, "notification_prefs/bob"),
      {reactions: false}));
  await assertSucceeds(deleteDoc(ref));

  await assertSucceeds(setDoc(ref, {comments: false}));
  for (const fs of [
    env.authenticatedContext("bob").firestore(),
    env.unauthenticatedContext().firestore(),
  ]) {
    await assertFails(getDoc(doc(fs, "notification_prefs/alice")));
    await assertFails(setDoc(doc(fs, "notification_prefs/alice"),
        {comments: true}));
    await assertFails(getDocs(collection(fs, "notification_prefs")));
  }
});

test("prefs rules: no prefs writes once account deletion has started", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "account_deletions/alice"),
        {startedAt: 1});
  });
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(alice, "notification_prefs/alice"),
      {reactions: false}));
});
