const http2 = require("node:http2");
const crypto = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");

// Keeps the lock-screen BAC current while the app is asleep. iOS never runs
// the Live Activity's own code, so its number only changes when the app runs
// or a push arrives. The app sends its projected BAC curve (one value every
// five minutes until sober) plus the activity's push token; a scheduled job
// pushes the value for "now". The server does no BAC maths of its own, so the
// lock screen always matches the app's model.

const COLLECTION = "live_activities";
const MAX_SAMPLES = 300;
const MAX_TEMPLATE_BYTES = 3000; // APNs caps a Live Activity payload at 4 KB.
const APPLE_EPOCH_OFFSET = 978307200; // 2001-01-01 in Unix seconds.
const STALE_AFTER_SECONDS = 600;

/**
 * @param {string} message
 * @return {HttpsError}
 */
function invalid(message) {
  return new HttpsError("invalid-argument", message);
}

/**
 * Checks an APNs device token and environment, shared by every push feature.
 * @param {*} token the hex token
 * @param {*} environment "production" or "sandbox"
 */
function validatePushToken(token, environment) {
  if (typeof token !== "string" || !/^[0-9a-f]{32,400}$/.test(token)) {
    throw invalid("Invalid push token.");
  }
  if (environment !== "production" && environment !== "sandbox") {
    throw invalid("Invalid environment.");
  }
}

/**
 * Checks a syncLiveActivity request. Returns null when the client is telling
 * the server to stop (no token or no curve), else the document to store.
 * @param {object} data the callable payload
 * @return {?object} the document, or null to delete
 */
function parseSync(data) {
  if (!data || typeof data !== "object") throw invalid("Invalid request.");
  const {token, template, samples, environment} = data;
  if (token == null || !Array.isArray(samples) || samples.length === 0) {
    return null;
  }
  validatePushToken(token, environment);
  if (!template || typeof template !== "object" || Array.isArray(template)) {
    throw invalid("Invalid template.");
  }
  if (Buffer.byteLength(JSON.stringify(template)) > MAX_TEMPLATE_BYTES) {
    throw invalid("Template too large.");
  }
  if (samples.length > MAX_SAMPLES) throw invalid("Too many samples.");
  const clean = samples.map((s) => {
    if (!s || typeof s !== "object") throw invalid("Invalid sample.");
    const {t, b, s: stage, c} = s;
    if (!Number.isFinite(t) || !Number.isFinite(b) || b < 0 || b > 1) {
      throw invalid("Invalid sample.");
    }
    if (typeof stage !== "string" || stage.length > 40) {
      throw invalid("Invalid sample.");
    }
    if (typeof c !== "string" || !/^#[0-9A-Fa-f]{6}$/.test(c)) {
      throw invalid("Invalid sample.");
    }
    return {t, b, s: stage, c};
  });
  for (let i = 1; i < clean.length; i++) {
    if (clean[i].t <= clean[i - 1].t) throw invalid("Samples out of order.");
  }
  return {
    token,
    environment,
    template,
    samples: clean,
    expiresAt: (clean[clean.length - 1].t + STALE_AFTER_SECONDS) * 1000,
  };
}

/**
 * The lock-screen state for `nowSeconds`: the template with BAC interpolated
 * between the two samples around now, and the stage of the sample just before.
 * `final` is true once the curve has run out (sober), the last push to send.
 * @param {object} doc the stored document
 * @param {number} nowSeconds Unix time
 * @return {{state: object, final: boolean}}
 */
function stateAt(doc, nowSeconds) {
  const samples = doc.samples;
  let i = 0;
  while (i + 1 < samples.length && samples[i + 1].t <= nowSeconds) i++;
  const at = samples[i];
  const next = samples[i + 1];
  let bac = at.b;
  if (next && nowSeconds > at.t) {
    const f = (nowSeconds - at.t) / (next.t - at.t);
    bac = at.b + (next.b - at.b) * f;
  }
  const final = !next && nowSeconds >= at.t;
  const state = {...doc.template};
  state.bac = Math.max(0, Math.round(bac * 100000) / 100000);
  state.stageName = at.s;
  state.stageColorHex = at.c;
  state.updatedAt = nowSeconds - APPLE_EPOCH_OFFSET;
  if (typeof doc.template.startedAt === "number") {
    const started = doc.template.startedAt + APPLE_EPOCH_OFFSET;
    state.elapsedMinutes = Math.max(0, Math.floor((nowSeconds - started) / 60));
  }
  return {state, final};
}

/**
 * The APNs request body for a Live Activity update.
 * @param {object} state the ContentState, with dates as Apple-epoch seconds
 * @param {number} nowSeconds Unix time
 * @return {object}
 */
function apnsPayload(state, nowSeconds) {
  return {
    "aps": {
      "timestamp": nowSeconds,
      "event": "update",
      "content-state": state,
      "stale-date": nowSeconds + STALE_AFTER_SECONDS,
    },
  };
}

/**
 * A provider token for APNs (ES256 JWT). Apple wants it refreshed at most
 * every 60 minutes, and not more often than every 20.
 * @param {{key: string, keyId: string, teamId: string, nowSeconds: number}} o
 * @return {string}
 */
function apnsJwt({key, keyId, teamId, nowSeconds}) {
  const b64 = (obj) => Buffer.from(JSON.stringify(obj)).toString("base64url");
  const body = `${b64({alg: "ES256", kid: keyId})}.${b64({
    iss: teamId,
    iat: nowSeconds,
  })}`;
  const sig = crypto.sign("sha256", Buffer.from(body), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${body}.${sig.toString("base64url")}`;
}

/**
 * The HTTP/2 request headers for one APNs push.
 * @param {{jwt: string, topic: string, token: string, pushType: ?string}} o
 * @return {object}
 */
function apnsHeaders({jwt, topic, token, pushType = "liveactivity"}) {
  return {
    ":method": "POST",
    ":path": `/3/device/${token}`,
    "authorization": `bearer ${jwt}`,
    "apns-push-type": pushType,
    "apns-topic": topic,
    "apns-priority": "10",
    "content-type": "application/json",
  };
}

/**
 * Sends pushes over one HTTP/2 connection per APNs environment.
 * @param {{jwt: string, topic: string, pushType: ?string}} o
 * @return {{send: Function, close: Function}}
 */
function apnsClient({jwt, topic, pushType = "liveactivity"}) {
  const sessions = {};
  const session = (environment) => {
    if (!sessions[environment]) {
      const host = environment === "sandbox" ?
        "https://api.sandbox.push.apple.com" :
        "https://api.push.apple.com";
      sessions[environment] = http2.connect(host);
      sessions[environment].on("error", () => {});
    }
    return sessions[environment];
  };
  const send = (environment, token, payload) => new Promise((resolve) => {
    const req = session(environment).request(
        apnsHeaders({jwt, topic, token, pushType}),
    );
    let status = 0;
    let body = "";
    req.setTimeout(10000, () => req.close());
    req.on("response", (headers) => {
      status = headers[":status"];
    });
    req.on("data", (chunk) => {
      body += chunk;
    });
    req.on("end", () => {
      let reason = "";
      try {
        reason = JSON.parse(body).reason || "";
      } catch (_) {
        // empty body on success
      }
      resolve({status, reason});
    });
    req.on("error", () => resolve({status: 0, reason: "network"}));
    req.end(JSON.stringify(payload));
  });
  const close = () => Object.values(sessions).forEach((s) => s.close());
  return {send, close};
}

/**
 * APNs answers that mean the token will never work again.
 * @param {{status: number, reason: string}} result
 * @return {boolean}
 */
function tokenIsDead({status, reason}) {
  return status === 410 ||
    reason === "BadDeviceToken" ||
    reason === "DeviceTokenNotForTopic" ||
    reason === "ExpiredToken";
}

/**
 * Stores (or clears) a user's lock-screen curve.
 * @param {{db: object, uid: string, data: object}} o
 * @return {Promise<object>}
 */
async function syncLiveActivity({db, uid, data}) {
  const doc = parseSync(data);
  const ref = db.collection(COLLECTION).doc(uid);
  if (!doc) {
    await ref.delete();
    return {ok: true, active: false};
  }
  await ref.set({...doc, updatedAt: Date.now()});
  return {ok: true, active: true};
}

/**
 * One run of the scheduled job: push the current value to every live night,
 * and drop the ones that are over or whose token died.
 * @param {{db: object, nowMs: number, send: Function}} o
 * @return {Promise<{sent: number, removed: number}>}
 */
async function pushDue({db, nowMs, send}) {
  const nowSeconds = Math.floor(nowMs / 1000);
  const col = db.collection(COLLECTION);
  let removed = 0;
  const expired = await col.where("expiresAt", "<=", nowMs).get();
  await Promise.all(expired.docs.map((d) => {
    removed++;
    return d.ref.delete();
  }));
  const live = await col.where("expiresAt", ">", nowMs).get();
  let sent = 0;
  await Promise.all(live.docs.map(async (d) => {
    const doc = d.data();
    const {state, final} = stateAt(doc, nowSeconds);
    const result = await send(
        doc.environment, doc.token, apnsPayload(state, nowSeconds));
    if (result.status === 200) sent++;
    if (final || tokenIsDead(result)) {
      removed++;
      await d.ref.delete();
    }
  }));
  return {sent, removed};
}

module.exports = {
  COLLECTION,
  APPLE_EPOCH_OFFSET,
  parseSync,
  validatePushToken,
  apnsHeaders,
  stateAt,
  apnsPayload,
  apnsJwt,
  apnsClient,
  tokenIsDead,
  syncLiveActivity,
  pushDue,
};
