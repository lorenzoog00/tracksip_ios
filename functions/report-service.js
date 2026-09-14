const {randomUUID, createHash} = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const {validateRequest, reserveQuota} = require("./report-policy");

// eslint-disable-next-line require-jsdoc
async function generateReport({
  db,
  uid,
  data,
  purchase,
  generate,
  now = Date.now,
}) {
  const {kind, id, payload} = validateRequest(data);
  const root = db.doc(`users/${uid}`);
  const deletion = db.doc(`account_deletions/${uid}`);
  const job = root
      .collection("report_jobs")
      .doc(createHash("sha256").update(`${kind}:${id}`).digest("hex"));
  const usage = root.collection("report_usage").doc("current");
  const owner = purchase ? db.doc(`purchase_owners/${purchase.key}`) : null;
  const collection =
    kind === "night" ?
      "night_events" :
      kind === "recovery" ?
        "night_recoveries" :
        "ai_coach_reports";
  const target = root.collection(collection).doc(id);
  const token = randomUUID();
  const claim = await db.runTransaction(async (tx) => {
    const [deleted, existing, counters, result] = await Promise.all([
      tx.get(deletion),
      tx.get(job),
      tx.get(usage),
      tx.get(target),
    ]);
    const previousOwner = owner ? await tx.get(owner) : null;
    if (deleted.exists) {
      throw new HttpsError(
          "failed-precondition",
          "Account deletion is in progress.",
      );
    }
    if (
      previousOwner &&
      previousOwner.exists &&
      previousOwner.data().uid !== uid
    ) {
      throw new HttpsError(
          "permission-denied",
          "This purchase is linked to another account.",
      );
    }
    if (kind === "night" && !result.exists) {
      throw new HttpsError(
          "not-found",
          "Sync this night before requesting a report.",
      );
    }
    const report = result.data()?.[kind === "night" ? "ai_report" : "report"];
    if (report) return {report};
    const old = existing.data() || {};
    if (old.status === "processing" && old.leaseUntil > now()) {
      return {pending: true};
    }
    if ((old.attempts || 0) >= 3) {
      throw new HttpsError(
          "resource-exhausted",
          "This report could not be completed after three attempts.",
      );
    }
    tx.set(usage, reserveQuota(counters.data() || {}, kind, !!purchase, now()));
    if (owner) tx.set(owner, {uid});
    tx.set(job, {
      status: "processing",
      token,
      attempts: (old.attempts || 0) + 1,
      leaseUntil: now() + 150000,
    });
    return {claimed: true};
  });
  if (!claim.claimed) return claim;
  try {
    const report = await generate(kind, payload);
    if (typeof report !== "string" || !report.trim() || report.length > 12000) {
      throw new Error("Invalid model response");
    }
    await db.runTransaction(async (tx) => {
      const [deleted, current, result] = await Promise.all([
        tx.get(deletion),
        tx.get(job),
        tx.get(target),
      ]);
      if (
        deleted.exists ||
        current.data()?.token !== token ||
        (kind === "night" && !result.exists)
      ) {
        throw new HttpsError("aborted", "Report request was cancelled.");
      }
      if (kind === "night") {
        tx.update(target, {ai_report: report});
      } else {
        const metadata = {};
        for (const key of [
          "period_start",
          "period_end",
          "event_a_id",
          "event_b_id",
        ]) {
          if (data.metadata?.[key] !== undefined) {
            metadata[key] = data.metadata[key];
          }
        }
        tx.set(target, {...metadata, type: kind, created_at: now(), report});
      }
      tx.update(job, {status: "complete", leaseUntil: 0});
    });
    return {report};
  } catch (error) {
    await db.runTransaction(async (tx) => {
      const [deleted, current] = await Promise.all([
        tx.get(deletion),
        tx.get(job),
      ]);
      if (!deleted.exists && current.data()?.token === token) {
        tx.update(job, {status: "failed", leaseUntil: 0});
      }
    });
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
        "unavailable",
        "Report could not be completed. Please try again.",
    );
  }
}

module.exports = {generateReport};
