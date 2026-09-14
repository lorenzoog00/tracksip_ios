const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {
  defineSecret,
  defineString,
  defineInt,
  defineBoolean,
} = require("firebase-functions/params");
const admin = require("firebase-admin");
const {Anthropic} = require("@anthropic-ai/sdk");
const {generateReport} = require("./report-service");
const {deleteAccount} = require("./accounts");
const {verifyPurchase} = require("./purchases");
const {validateRequest} = require("./report-policy");
const {buildPrompt} = require("./prompts");

admin.initializeApp();
setGlobalOptions({region: "us-central1", maxInstances: 10});
const claudeKey = defineSecret("CLAUDE_API_KEY");
const appleKey = defineSecret("APPLE_IAP_PRIVATE_KEY");
const keyId = defineString("APPLE_IAP_KEY_ID");
const issuerId = defineString("APPLE_IAP_ISSUER_ID");
const appAppleId = defineInt("APPLE_APP_ID");
const allowSandbox = defineBoolean("APPLE_ALLOW_SANDBOX", {default: false});

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
      validateRequest(request.data);
      const db = admin.firestore();
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
        generate: async (kind, data) => {
          const prompt = buildPrompt(kind, data);
          const client = new Anthropic({
            apiKey: claudeKey.value(),
            timeout: 25000,
            maxRetries: 1,
          });
          const response = await client.messages.create({
            model: "claude-haiku-4-5-20251001",
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

exports.deleteAccount = onCall(
    {timeoutSeconds: 120, enforceAppCheck: true},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "Please sign in.");
      }
      return deleteAccount({
        db: admin.firestore(),
        auth: admin.auth(),
        uid: request.auth.uid,
        authTime: request.auth.token.auth_time,
      });
    },
);
