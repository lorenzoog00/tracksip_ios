const {readFileSync} = require("node:fs");
const {join} = require("node:path");
const {createHash} = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const {
  SignedDataVerifier,
  AppStoreServerAPIClient,
  Environment,
} = require("@apple/app-store-server-library");
const {activePurchase} = require("./report-policy");

// eslint-disable-next-line require-jsdoc
function accountToken(uid) {
  const hex = createHash("sha256").update(uid).digest("hex").slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// eslint-disable-next-line require-jsdoc
async function verifyPurchase(signed, uid, config) {
  if (!signed) return null;
  if (typeof signed !== "string" || signed.length > 20000) {
    throw new HttpsError("invalid-argument", "Invalid purchase proof.");
  }
  const roots = ["AppleRootCA-G2.cer", "AppleRootCA-G3.cer"].map((name) =>
    readFileSync(join(__dirname, "certificates", name)),
  );
  const environments = [Environment.PRODUCTION];
  if (config.allowSandbox) environments.push(Environment.SANDBOX);
  for (const environment of environments) {
    const verifier = new SignedDataVerifier(
        roots,
        true,
        environment,
        "com.lorenzoog.siptrack",
        config.appAppleId,
    );
    let proof;
    try {
      proof = await verifier.verifyAndDecodeTransaction(signed);
    } catch (_) {
      continue; // Try only explicitly configured Apple environments.
    }
    if (
      proof.appAccountToken &&
      proof.appAccountToken.toLowerCase() !== accountToken(uid)
    ) {
      throw new HttpsError(
          "permission-denied",
          "This purchase belongs to another account.",
      );
    }
    const client = new AppStoreServerAPIClient(
        config.key,
        config.keyId,
        config.issuerId,
        "com.lorenzoog.siptrack",
        environment,
    );
    // Re-read from Apple to detect refunds after the receipt was signed.
    const response = await client.getTransactionInfo(proof.transactionId);
    const current = await verifier.verifyAndDecodeTransaction(
        response.signedTransactionInfo,
    );
    if (
      current.appAccountToken &&
      current.appAccountToken.toLowerCase() !== accountToken(uid)
    ) {
      throw new HttpsError(
          "permission-denied",
          "This purchase belongs to another account.",
      );
    }
    if (
      current.transactionId !== proof.transactionId ||
      current.originalTransactionId !== proof.originalTransactionId
    ) {
      throw new HttpsError(
          "permission-denied",
          "Purchase verification failed.",
      );
    }
    if (!activePurchase(current)) return null;
    return {key: `${environment}-${current.originalTransactionId}`};
  }
  // No configured environment could verify the signature. That covers a forged
  // proof and, while allowSandbox is false, a sandbox purchase such as the one
  // an App Review tester makes. Fall through to the free tier rather than
  // throwing: an unverifiable proof must never grant paid access, but it must
  // not break the app for someone who has just paid either. Throwing here put
  // "Purchase could not be verified. Restore purchases and try again." in front
  // of a reviewer seconds after they subscribed. Degrading matches what an
  // expired or refunded purchase already does above.
  return null;
}

module.exports = {verifyPurchase, accountToken};
