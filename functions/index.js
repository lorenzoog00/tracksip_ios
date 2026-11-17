const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  defineSecret,
  defineString,
  defineInt,
  defineBoolean,
} = require("firebase-functions/params");
// firebase-admin 14 removed the namespaced API. The old calls parsed, linted
// and deployed cleanly, then threw on the first real request and reached the
// app as a bare "Internal". Import each service's modular entry point instead.
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const {ImageAnnotatorClient} = require("@google-cloud/vision");
const {Anthropic} = require("@anthropic-ai/sdk");
const {generateReport} = require("./report-service");
const {deleteAccount} = require("./accounts");
const {verifyPurchase} = require("./purchases");
const {
  validateRequest,
  isProTester,
  assertPromptFits,
} = require("./report-policy");
const {lookupDrink} = require("./drink-lookup");
const {buildPrompt} = require("./prompts");
const liveActivity = require("./live-activity");
const social = require("./social");
const {setAvatar} = require("./avatar");

initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});
const claudeKey = defineSecret("CLAUDE_API_KEY");
const appleKey = defineSecret("APPLE_IAP_PRIVATE_KEY");
const keyId = defineString("APPLE_IAP_KEY_ID");
const issuerId = defineString("APPLE_IAP_ISSUER_ID");
const appAppleId = defineInt("APPLE_APP_ID");
const allowSandbox = defineBoolean("APPLE_ALLOW_SANDBOX", {default: false});
// Uids billed as paid without a verifiable receipt. A TestFlight purchase is
// a sandbox one and cannot be verified while allowSandbox is false, which
// left our own testers on the free tier. Server configuration only.
const proTesters = defineString("PRO_TESTER_UIDS", {default: ""});
// APNs auth key (.p8) for lock-screen pushes. Separate from the App Store
// Connect key above: Apple issues push keys under Certificates, IDs & Profiles.
const apnsKey = defineSecret("APNS_AUTH_KEY");
const apnsKeyId = defineString("APNS_KEY_ID");
const appleTeamId = defineString("APPLE_TEAM_ID", {default: "6T5DB8M42N"});
const liveActivityTopic = defineString("LIVE_ACTIVITY_TOPIC", {
  default: "com.lorenzoog.siptrack.push-type.liveactivity",
});

exports.requestReport = onCall(
    {
      secrets: [claudeKey, appleKey],
      timeoutSeconds: 120,
      enforceAppCheck: true,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      const {kind: reportKind, payload} = validateRequest(request.data);
      // Before any quota is reserved: an oversized prompt is refused, so it
      // must not also cost the caller one of their reports. The guard inside
      // `generate` below is the billing boundary; this one is the fair one.
      const preview = buildPrompt(reportKind, payload);
      assertPromptFits(preview.system, preview.prompt);
      const db = getFirestore();
      if ((await db.doc(`account_deletions/${request.auth.uid}`).get()).exists) {
        throw new HttpsError(
            "failed-precondition",
            "Account deletion is in progress.",
        );
      }
      const purchase = await verifyPurchase(
          request.data.signedTransaction,
          request.auth.uid,
          {
            key: appleKey.value(),
            keyId: keyId.value(),
            issuerId: issuerId.value(),
            appAppleId: appAppleId.value(),
            allowSandbox: allowSandbox.value(),
          },
      );
      return generateReport({
        db,
        uid: request.auth.uid,
        data: request.data,
        purchase,
        tester: isProTester(request.auth.uid, proTesters.value()),
        generate: async (kind, data) => {
          const prompt = buildPrompt(kind, data);
          // What we pay for is this prompt, not the payload it came
          // from; the two sizes are not the same.
          assertPromptFits(prompt.system, prompt.prompt);
          const client = new Anthropic({
            apiKey: claudeKey.value(),
            timeout: 25000,
            maxRetries: 1,
          });
          const response = await client.messages.create({
            // claude-haiku-5-5 costs $0.10/$0.50 per MTok against Haiku 4.5's
            // $1/$5 — a tenth, for the same short summaries. Thinking is on by
            // default on this model and is billed as output, so it is turned
            // off: these reports are one short pass over a fixed field list,
            // not reasoning work. Keep max_tokens in step with
            // MAX_OUTPUT_TOKENS in report-policy.js, which prices the caps.
            model: "claude-haiku-5-5",
            thinking: {type: "disabled"},
            max_tokens: 700,
            system: prompt.system,
            messages: [{role: "user", content: prompt.prompt}],
          });
          return response.content
              .filter((block) => block.type === "text")
              .map((block) => block.text)
              .join("\n");
        },
      });
    },
);

exports.lookupDrink = onCall(
    {
      secrets: [claudeKey, appleKey],
      timeoutSeconds: 30,
      enforceAppCheck: true,
    },
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      const purchase = await verifyPurchase(
          request.data?.signedTransaction,
          request.auth.uid,
          {
            key: appleKey.value(),
            keyId: keyId.value(),
            issuerId: issuerId.value(),
            appAppleId: appAppleId.value(),
            allowSandbox: allowSandbox.value(),
          },
      );
      return lookupDrink({
        db: getFirestore(),
        uid: request.auth.uid,
        data: request.data,
        purchase,
        tester: isProTester(request.auth.uid, proTesters.value()),
        generate: async (prompt) => {
          const client = new Anthropic({
            apiKey: claudeKey.value(),
            timeout: 20000,
            maxRetries: 1,
          });
          const response = await client.messages.create({
            // Same model and the same reasons as the report above. Keep
            // max_tokens in step with MAX_OUTPUT_TOKENS in drink-lookup.js.
            model: "claude-haiku-5-5",
            thinking: {type: "disabled"},
            max_tokens: 200,
            system: prompt.system,
            messages: [{role: "user", content: prompt.prompt}],
          });
          return response.content
              .filter((block) => block.type === "text")
              .map((block) => block.text)
              .join("\n");
        },
      });
    },
);

exports.deleteAccount = onCall(
    {timeoutSeconds: 120, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      return deleteAccount({
        db: getFirestore(),
        auth: getAuth(),
        bucket: getStorage().bucket(),
        uid: request.auth.uid,
        authTime: request.auth.token.auth_time,
      });
    },
);

exports.syncLiveActivity = onCall(
    {timeoutSeconds: 30, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      return liveActivity.syncLiveActivity({
        db: getFirestore(),
        uid: request.auth.uid,
        data: request.data,
      });
    },
);

// Every 5 minutes, push each live night's current BAC to its lock screen.
exports.pushLiveActivities = onSchedule(
    {schedule: "every 5 minutes", secrets: [apnsKey], timeoutSeconds: 120},
    async () => {
      const nowMs = Date.now();
      const client = liveActivity.apnsClient({
        jwt: liveActivity.apnsJwt({
          key: apnsKey.value(),
          keyId: apnsKeyId.value(),
          teamId: appleTeamId.value(),
          nowSeconds: Math.floor(nowMs / 1000),
        }),
        topic: liveActivityTopic.value(),
      });
      try {
        await liveActivity.pushDue({
          db: getFirestore(),
          nowMs,
          send: client.send,
        });
      } finally {
        client.close();
      }
    },
);

// Friends v1. Each callable is a thin shell: auth check, then social.js.
const socialCallable = (fn) => onCall(
    {timeoutSeconds: 30, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      return social[fn]({
        db: getFirestore(),
        uid: request.auth.uid,
        data: request.data,
      });
    },
);

// Request and accept pushes go out with an APNs client built per call. A
// bad key or config only loses the push, never the friendship write.
const alertPushClient = () => {
  try {
    return liveActivity.apnsClient({
      jwt: liveActivity.apnsJwt({
        key: apnsKey.value(),
        keyId: apnsKeyId.value(),
        teamId: appleTeamId.value(),
        nowSeconds: Math.floor(Date.now() / 1000),
      }),
      topic: "com.lorenzoog.siptrack",
      pushType: "alert",
    });
  } catch (error) {
    console.error("APNs client setup failed; pushes skipped", error);
    return null;
  }
};

const pushingCallable = (fn) => onCall(
    {secrets: [apnsKey], timeoutSeconds: 30, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      const client = alertPushClient();
      try {
        const db = getFirestore();
        return await social[fn]({
          db,
          uid: request.auth.uid,
          data: request.data,
          notify: client ?
            social.notifyFromPushTokens({db, send: client.send}) :
            async () => {},
        });
      } finally {
        if (client) client.close();
      }
    },
);

exports.claimUsername = socialCallable("claimUsername");
exports.searchUsers = socialCallable("searchUsers");
exports.cancelFriendRequest = socialCallable("cancelFriendRequest");
exports.removeFriend = socialCallable("removeFriend");
exports.blockUser = socialCallable("blockUser");
exports.unblockUser = socialCallable("unblockUser");
exports.reportUser = socialCallable("reportUser");
exports.registerPushToken = socialCallable("registerPushToken");
exports.sendFriendRequest = pushingCallable("sendFriendRequest");
exports.respondToFriendRequest = pushingCallable("respondToFriendRequest");

let visionClient;
// Likelihood strings per category, as the avatar moderation expects.
const safeSearch = async (buffer) => {
  visionClient = visionClient || new ImageAnnotatorClient();
  const [result] = await visionClient.safeSearchDetection({
    image: {content: buffer},
  });
  // A per-image failure comes back as result.error, not a throw. Throwing
  // here lands in setAvatar's fail-closed "unavailable" path.
  if (!result || result.error || !result.safeSearchAnnotation) {
    throw new Error(
        `SafeSearch returned no verdict: ${result && result.error ?
          result.error.message : "missing annotation"}`);
  }
  const {adult, violence, racy} = result.safeSearchAnnotation;
  return {adult, violence, racy};
};

exports.setAvatar = onCall(
    {timeoutSeconds: 30, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      return setAvatar({
        db: getFirestore(),
        bucket: getStorage().bucket(),
        uid: request.auth.uid,
        data: request.data,
        safeSearch,
      });
    },
);
