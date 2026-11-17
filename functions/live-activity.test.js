const {test} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const la = require("./live-activity");

const TOKEN = "ab".repeat(32);
const sample = (t, b, s = "Buzzed", c = "#FFA502") => ({t, b, s, c});
const request = (over = {}) => ({
  token: TOKEN,
  environment: "production",
  template: {bac: 0.05, drinkCount: 2, startedAt: 1000, quickDrinks: []},
  samples: [sample(1000, 0.05), sample(1300, 0.04), sample(1600, 0)],
  ...over,
});

test("a request without a token or curve means stop", () => {
  assert.equal(la.parseSync(request({token: null})), null);
  assert.equal(la.parseSync(request({samples: []})), null);
});

test("a valid request becomes a document that expires after the curve", () => {
  const doc = la.parseSync(request());
  assert.equal(doc.token, TOKEN);
  assert.equal(doc.samples.length, 3);
  assert.equal(doc.expiresAt, (1600 + 600) * 1000);
});

test("bad input is rejected", () => {
  const bad = [
    {token: "not-hex"},
    {environment: "staging"},
    {template: []},
    {template: {pad: "x".repeat(4000)}},
    {samples: [sample(1000, 2)]},
    {samples: [sample(1000, 0.1, "Buzzed", "red")]},
    {samples: [sample(1300, 0.1), sample(1000, 0.05)]},
    {samples: Array.from({length: 301}, (_, i) => sample(i, 0.01))},
  ];
  for (const over of bad) {
    assert.throws(() => la.parseSync(request(over)), /invalid|Too|too|order/i);
  }
});

test("BAC is interpolated between the samples around now", () => {
  const doc = la.parseSync(request());
  const {state, final} = la.stateAt(doc, 1150);
  assert.equal(state.bac, 0.045);
  assert.equal(state.stageName, "Buzzed");
  assert.equal(state.drinkCount, 2, "the rest of the template is kept");
  assert.equal(final, false);
});

test("dates in the pushed state use Apple's 2001 epoch, as ActivityKit decodes", () => {
  const doc = la.parseSync(request());
  const now = 1150;
  const {state} = la.stateAt(doc, now);
  assert.equal(state.updatedAt, now - la.APPLE_EPOCH_OFFSET);
  const startedUnix = 1000 + la.APPLE_EPOCH_OFFSET;
  const startedApple = startedUnix - la.APPLE_EPOCH_OFFSET;
  const doc2 = la.parseSync(request({
    template: {startedAt: startedApple},
  }));
  assert.equal(
      la.stateAt(doc2, startedUnix + 30 * 60).state.elapsedMinutes, 30);
});

test("past the last sample the state is sober and final", () => {
  const doc = la.parseSync(request());
  const {state, final} = la.stateAt(doc, 2000);
  assert.equal(state.bac, 0);
  assert.equal(final, true);
});

test("the APNs payload is a Live Activity update with a stale date", () => {
  const p = la.apnsPayload({bac: 0.01}, 5000);
  assert.equal(p.aps.event, "update");
  assert.equal(p.aps.timestamp, 5000);
  assert.equal(p.aps["stale-date"], 5600);
  assert.deepEqual(p.aps["content-state"], {bac: 0.01});
});

test("the provider token is an ES256 JWT that verifies with the key", () => {
  const {privateKey, publicKey} = crypto.generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const key = privateKey.export({type: "pkcs8", format: "pem"});
  const jwt = la.apnsJwt({key, keyId: "KEY123", teamId: "TEAM", nowSeconds: 7});
  const [h, c, s] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(h, "base64url")), {
    alg: "ES256", kid: "KEY123",
  });
  assert.deepEqual(JSON.parse(Buffer.from(c, "base64url")), {
    iss: "TEAM", iat: 7,
  });
  assert.ok(crypto.verify("sha256", Buffer.from(`${h}.${c}`), {
    key: publicKey, dsaEncoding: "ieee-p1363",
  }, Buffer.from(s, "base64url")));
});

// A tiny in-memory stand-in for the slice of Firestore these use.
// eslint-disable-next-line require-jsdoc
function fakeDb(initial = {}) {
  const docs = new Map(Object.entries(initial));
  const ref = (id) => ({
    id,
    set: async (v) => void docs.set(id, v),
    delete: async () => void docs.delete(id),
  });
  const snap = (pred) => ({
    docs: [...docs.entries()].filter(([, v]) => pred(v))
        .map(([id, v]) => ({ref: ref(id), data: () => v})),
  });
  return {
    docs,
    collection: (name) => {
      assert.equal(name, la.COLLECTION);
      return {
        doc: ref,
        where: (field, op, value) => ({
          get: async () => snap((v) => op === "<=" ?
            v[field] <= value : v[field] > value),
        }),
      };
    },
  };
}

test("sync stores the curve per user and clears it on stop", async () => {
  const db = fakeDb();
  await la.syncLiveActivity({db, uid: "u1", data: request()});
  assert.equal(db.docs.get("u1").token, TOKEN);
  await la.syncLiveActivity({db, uid: "u1", data: {samples: []}});
  assert.equal(db.docs.has("u1"), false);
});

test("the job pushes live nights and drops finished or dead ones", async () => {
  const live = la.parseSync(request());
  const dead = la.parseSync(request({token: "cd".repeat(32)}));
  const old = {...live, expiresAt: 1};
  const db = fakeDb({live, dead, old});
  const sent = [];
  const send = async (env, token, payload) => {
    sent.push({env, token, bac: payload.aps["content-state"].bac});
    return token === TOKEN ? {status: 200, reason: ""} :
      {status: 410, reason: "Unregistered"};
  };
  const result = await la.pushDue({db, nowMs: 1150 * 1000, send});
  assert.equal(result.sent, 1);
  assert.deepEqual([...db.docs.keys()], ["live"]);
  assert.equal(sent.find((s) => s.token === TOKEN).bac, 0.045);
});

test("the last push of a night removes it", async () => {
  const db = fakeDb({u: la.parseSync(request())});
  await la.pushDue({db, nowMs: 1700 * 1000, send: async () => ({status: 200})});
  assert.equal(db.docs.size, 0);
});

test("apnsHeaders defaults to a live activity push", () => {
  const h = la.apnsHeaders({jwt: "J", topic: "com.x", token: "ab"});
  assert.equal(h["apns-push-type"], "liveactivity");
  assert.equal(h[":path"], "/3/device/ab");
  assert.equal(h.authorization, "bearer J");
  assert.equal(h["apns-topic"], "com.x");
});

test("apnsHeaders honours an alert push type", () => {
  const h = la.apnsHeaders({
    jwt: "J", topic: "com.x", token: "ab", pushType: "alert",
  });
  assert.equal(h["apns-push-type"], "alert");
});

test("parseSync and validatePushToken share token rules", () => {
  assert.doesNotThrow(() => la.validatePushToken(TOKEN, "sandbox"));
  assert.throws(() => la.validatePushToken("zz", "sandbox"), /token/i);
  assert.throws(() => la.validatePushToken(TOKEN, "staging"), /environment/i);
});
