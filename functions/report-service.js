const {randomUUID, createHash} = require("node:crypto");
const {HttpsError} = require("firebase-functions/v2/https");
const {
  validateRequest,
  reserveQuota,
  remainingQuota,
} = require("./report-policy");
const {formatAlcoholLog, ALCOHOL_LOG_HEADING} = require("./prompts");

// eslint-disable-next-line require-jsdoc
async function generateReport({
  db,
  uid,
  data,
  purchase,
  tester = false,
  generate,
  now = Date.now,
}) {
  const {kind, id, payload} = validateRequest(data);
  const doseVersion = kind === "night" && payload.alcoholDose ? 1 : 0;
  const root = db.doc(`users/${uid}`);
  const deletion = db.doc(`account_deletions/${uid}`);
  const job = root
      .collection("report_jobs")
      .doc(createHash("sha256").update(`${kind}:${id}`).digest("hex"));
  const usage = root.collection("report_usage").doc("current");
  const owner = purchase ? db.doc(`purchase_owners/${purchase.key}`) : null;
  const pro = !!purchase || tester;
  // A morning plan takes the place of the night's recovery brief.
  const collection =
    kind === "night" ?
      "night_events" :
      kind === "recovery" || kind === "morning" ?
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
    // An old build still asks for the recovery brief, and the brief would
    // replace the night's morning plan in the same doc. Refused before any
    // quota is reserved: the plan stays and nothing is spent.
    if (kind === "recovery" && result.data()?.type === "morning") {
      throw new HttpsError(
          "failed-precondition",
          "This night already has a morning recovery plan.",
      );
    }
    if (kind === "morning" && result.data()?.plan) {
      return {morning: result.data()};
    }
    // A morning request never answers with an old brief's text.
    const report = kind === "morning" ? null :
      result.data()?.[kind === "night" ? "ai_report" : "report"];
    const currentReport = typeof report === "string" &&
      report.startsWith(ALCOHOL_LOG_HEADING);
    if (report && (!doseVersion || currentReport)) {
      return {report};
    }
    const old = existing.data() || {};
    if (old.status === "processing" && old.leaseUntil > now()) {
      return {pending: true};
    }
    const sameVersion = (old.doseVersion || 0) === doseVersion;
    const attempts = sameVersion ? old.attempts || 0 : 0;
    if (attempts >= 3) {
      throw new HttpsError(
          "resource-exhausted",
          "This report could not be completed after three attempts.",
      );
    }
    const reserved = reserveQuota(counters.data() || {}, kind, pro, now());
    tx.set(usage, reserved);
    if (owner) tx.set(owner, {uid});
    tx.set(job, {
      status: "processing",
      token,
      attempts: attempts + 1,
      doseVersion,
      leaseUntil: now() + 150000,
    });
    return {claimed: true, counts: reserved.counts};
  });
  if (!claim.claimed) return claim;
  try {
    const body = await generate(kind, payload);
    // A morning plan comes back as the doc body; every other kind as text.
    if (kind === "morning" ?
      body === null || typeof body !== "object" || !body.plan :
      typeof body !== "string" || !body.trim() || body.length > 12000) {
      throw new Error("Invalid model response");
    }
    const report = doseVersion ? `${formatAlcoholLog(payload)}\n\n${body}` : body;
    let morning;
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
      // A morning plan saved while this brief was being written still wins.
      if (kind === "recovery" && result.data()?.type === "morning") {
        throw new HttpsError(
            "failed-precondition",
            "This night already has a morning recovery plan.",
        );
      }
      if (kind === "night") {
        tx.update(target, {ai_report: report});
      } else if (kind === "morning") {
        morning = {...body, type: "morning", version: 2, created_at: now()};
        tx.set(target, morning);
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
    if (kind === "morning") {
      return {morning, remaining: remainingQuota(claim.counts, kind, pro)};
    }
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
