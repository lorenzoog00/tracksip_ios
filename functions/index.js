const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
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
const {
  loadMorningContext,
  assertPlannable,
  finalizePlan,
} = require("./recovery/morning");
const {buildMorningPrompt} = require("./recovery/prompt");
const {PLAN_JSON_SCHEMA, parsePlan} = require("./recovery/plan");
const liveActivity = require("./live-activity");
const social = require("./social");
const interactions = require("./interactions");
const {setAvatar} = require("./avatar");
const {generatePhoto, completeLibraryPhoto} = require("./recovery/image");
const {
  requireAdmin,
  listPendingPhotos,
  reviewPhoto,
} = require("./recovery/review");

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
// Uids allowed to review recovery photos. Empty denies everyone.
const adminUids = defineString("ADMIN_UIDS", {default: ""});
// APNs auth key (.p8) for lock-screen pushes. Separate from the App Store
// Connect key above: Apple issues push keys under Certificates, IDs & Profiles.
const apnsKey = defineSecret("APNS_AUTH_KEY");
const apnsKeyId = defineString("APNS_KEY_ID");
const appleTeamId = defineString("APPLE_TEAM_ID", {default: "6T5DB8M42N"});
const liveActivityTopic = defineString("LIVE_ACTIVITY_TOPIC", {
  default: "com.lorenzoog.siptrack.push-type.liveactivity",
});
// New library photos generated per UTC day across the whole app. They are an
// app-wide cost, outside the per-user budget in report-policy.js; past the
// cap a new item is saved without a photo and the plan shows an icon tile.
const photoDailyCap = defineInt("PHOTO_DAILY_CAP", {default: 10});
// Vertex AI image model for new recovery library photos. Confirm the id
// before deploying: it is the newest Gemini image id the installed
// @google/genai lists.
const imageModel = defineString("IMAGE_MODEL", {
  default: "gemini-3.1-flash-image",
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
      const {
        kind: reportKind,
        id: eventId,
        payload,
      } = validateRequest(request.data);
      // Before any quota is reserved: an oversized prompt is refused, so it
      // must not also cost the caller one of their reports. The guard inside
      // `generate` below is the billing boundary; this one is the fair one.
      // A morning prompt needs the database, so it is checked further down.
      if (reportKind !== "morning") {
        const preview = buildPrompt(reportKind, payload);
        assertPromptFits(preview.system, preview.prompt);
      }
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
      // The morning prompt is built once, from the library and this user's
      // last 30 days, and is exactly what `generate` sends, so this one guard
      // is both the fair and the billing one. The schema travels with it and
      // is priced with it.
      let morning = null;
      if (reportKind === "morning") {
        const ctx = await loadMorningContext({
          db,
          uid: request.auth.uid,
          payload,
        });
        const prompt = buildMorningPrompt(ctx);
        assertPromptFits(
            prompt.system + JSON.stringify(PLAN_JSON_SCHEMA),
            prompt.prompt,
        );
        // Also a certain refusal, so also before any quota is reserved.
        assertPlannable(ctx);
        morning = {ctx, prompt};
      }
      return generateReport({
        db,
        uid: request.auth.uid,
        data: request.data,
        purchase,
        tester: isProTester(request.auth.uid, proTesters.value()),
        generate: async (kind, data) => {
          if (morning) {
            const client = new Anthropic({
              apiKey: claudeKey.value(),
              timeout: 25000,
              maxRetries: 1,
            });
            const response = await client.messages.create({
              // Same model, thinking and output cap as the reports below,
              // for the same reasons.
              model: "claude-haiku-5-5",
              thinking: {type: "disabled"},
              max_tokens: 700,
              system: morning.prompt.system,
              messages: [{role: "user", content: morning.prompt.prompt}],
              // Structured output holds the reply to the plan's shape.
              // parsePlan still checks every id and length; when it refuses
              // a reply it throws, which is a failed attempt the app retries.
              output_config: {
                format: {type: "json_schema", schema: PLAN_JSON_SCHEMA},
              },
            });
            // A cut-off reply (max_tokens) or a refusal fails parsePlan
            // below; logging why first tells the two apart from a bad plan.
            if (response.stop_reason !== "end_turn") {
              console.warn("morning plan: model stopped early", {
                stopReason: response.stop_reason,
                outputTokens: response.usage?.output_tokens,
              });
            }
            const text = response.content
                .filter((block) => block.type === "text")
                .map((block) => block.text)
                .join("\n");
            return finalizePlan({
              db,
              uid: request.auth.uid,
              eventId,
              parsed: parsePlan(text, morning.ctx),
              ctx: morning.ctx,
              now: Date.now(),
              dailyCap: photoDailyCap.value(),
            });
          }
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

// Friends v1. Each callable is a thin shell: auth check, then social.js (or
// interactions.js for night reactions and comments).
const socialCallable = (fn, handlers = social) => onCall(
    {timeoutSeconds: 30, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      return handlers[fn]({
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

const pushingCallable = (
    fn, handlers = social, notifier = social.notifyFromPushTokens,
) => onCall(
    {secrets: [apnsKey], timeoutSeconds: 30, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      const client = alertPushClient();
      try {
        const db = getFirestore();
        return await handlers[fn]({
          db,
          uid: request.auth.uid,
          data: request.data,
          notify: client ?
            notifier({db, send: client.send}) :
            async () => {},
        });
      } finally {
        if (client) client.close();
      }
    },
);

exports.claimUsername = socialCallable("claimUsername");
exports.suggestFriends = socialCallable("suggestFriends");
exports.searchUsers = socialCallable("searchUsers");
exports.cancelFriendRequest = socialCallable("cancelFriendRequest");
exports.removeFriend = socialCallable("removeFriend");
exports.blockUser = socialCallable("blockUser");
exports.unblockUser = socialCallable("unblockUser");
exports.reportUser = socialCallable("reportUser");
exports.registerPushToken = socialCallable("registerPushToken");
exports.unregisterPushToken = socialCallable("unregisterPushToken");
exports.sendFriendRequest = pushingCallable("sendFriendRequest");
exports.respondToFriendRequest = pushingCallable("respondToFriendRequest");

// Night reactions and comments. Reacting and commenting push the owner,
// earlier commenters and mentioned friends, so those two carry the APNs key.
exports.reactToNight = pushingCallable(
    "reactToNight", interactions, interactions.notifyThread);
exports.addComment = pushingCallable(
    "addComment", interactions, interactions.notifyThread);
exports.deleteComment = socialCallable("deleteComment", interactions);
exports.getNightThread = socialCallable("getNightThread", interactions);

// Going incognito, deleting the shared night or the account deletes
// shared_nights/{uid}; the thread of the night that doc held goes with it,
// unless that night's unexpired ended copy still shows it (cleanupEndedThread
// takes it when the copy goes). Earlier nights' threads stay on friends'
// feeds through their ended copies. A TTL delete fires
// this too, which is harmless: the rules hide a thread once its night has
// expired, and its own docs would be collected by TTL two days later.
exports.cleanupThreads = onDocumentDeleted(
    {document: "shared_nights/{uid}", timeoutSeconds: 120},
    (event) => interactions.deleteThreadOfNight({
      db: getFirestore(),
      uid: event.params.uid,
      night: event.data && event.data.data(),
    }),
);

// Deleting an ended copy (that night deleted or made incognito, TTL, account
// deletion) takes its thread, unless the main doc still holds that night.
exports.cleanupEndedThread = onDocumentDeleted(
    {document: "shared_nights/{uid}/ended/{started}", timeoutSeconds: 120},
    (event) => interactions.deleteThreadOfEndedCopy({
      db: getFirestore(),
      uid: event.params.uid,
      started: event.params.started,
    }),
);

/**
 * Accounts whose verified sign-in number is one of these (see
 * social.lookupPhoneOwners, which batches and skips a failed batch).
 * @param {string[]} phones E.164 numbers
 * @return {Promise<{uid: string, phone: string}[]>}
 */
function lookupPhoneOwners(phones) {
  return social.lookupPhoneOwners({auth: getAuth(), phones});
}

/**
 * Whether the caller has a verified number now. Reads the live account, not
 * the token, so a removed number stops matching at once.
 * @param {string} uid the caller
 * @return {Promise<boolean>}
 */
async function callerHasPhone(uid) {
  return Boolean((await getAuth().getUser(uid)).phoneNumber);
}

// Contacts are matched by phone number here and dropped: nothing from the list
// is stored or logged. Matched people may get a "@x is on TrackSip" push, so
// this one carries the APNs key like the friend-request callables.
exports.matchContacts = onCall(
    {secrets: [apnsKey], timeoutSeconds: 60, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      const client = alertPushClient();
      try {
        const db = getFirestore();
        return await social.matchContacts({
          db,
          uid: request.auth.uid,
          data: request.data,
          lookupPhones: lookupPhoneOwners,
          hasPhone: callerHasPhone,
          notify: client ?
            social.notifyFromPushTokens({db, send: client.send}) :
            async () => {},
        });
      } finally {
        if (client) client.close();
      }
    },
);

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

/**
 * Generates and stores one library photo, with the genai client built per run.
 * @param {string} itemId
 * @param {object} [options] `{versioned}`: regeneration writes a new path.
 * @return {Promise<void>}
 */
async function runLibraryPhoto(itemId, {versioned = false} = {}) {
  // Built per run, not at load, so a cold start that never needs it
  // does not pay for it.
  const {GoogleGenAI} = require("@google/genai");
  const genai = new GoogleGenAI({
    vertexai: true,
    project: process.env.GCLOUD_PROJECT,
    location: "us-central1",
  });
  await completeLibraryPhoto({
    db: getFirestore(),
    bucket: getStorage().bucket(),
    itemId,
    now: Date.now(),
    versioned,
    generate: (picked) =>
      generatePhoto(picked, {genai, model: imageModel.value()}),
  });
}

// A new library item needs a photo. The plan that proposed it is filled in by
// the same run, so the plan is returned without waiting for the image.
exports.generateLibraryPhoto = onDocumentCreated(
    {
      document: "recovery_library/{itemId}",
      memory: "1GiB",
      timeoutSeconds: 120,
    },
    async (event) => {
      const item = event.data && event.data.data();
      if (!item || item.photoStatus !== "generating") return;
      await runLibraryPhoto(event.params.itemId);
    },
);

exports.listPendingPhotos = onCall(
    {enforceAppCheck: true},
    async (request) => {
      requireAdmin(request.auth, adminUids.value());
      return listPendingPhotos({db: getFirestore()});
    },
);

exports.reviewPhoto = onCall(
    {enforceAppCheck: true, memory: "1GiB", timeoutSeconds: 120},
    async (request) => {
      requireAdmin(request.auth, adminUids.value());
      const {itemId, action} = request.data ?? {};
      return reviewPhoto({
        db: getFirestore(), itemId, action,
        regenerate: (id) => runLibraryPhoto(id, {versioned: true}),
      });
    },
);
