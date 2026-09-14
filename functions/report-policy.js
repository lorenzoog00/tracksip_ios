const {HttpsError} = require("firebase-functions/v2/https");

const PRODUCTS = new Set([
  "com.lorenzoog.siptrack.pro.monthly",
  "com.lorenzoog.siptrack.pro.yearly",
  "com.lorenzoog.siptrack.pro.lifetime",
]);
const FREE_LIMITS = {
  night: 5,
  recovery: 5,
  weekly: 5,
  monthly: 1,
  comparison: 5,
};

// eslint-disable-next-line require-jsdoc
function activePurchase(transaction, now = Date.now()) {
  return (
    PRODUCTS.has(transaction.productId) &&
    transaction.revocationDate == null &&
    !transaction.isUpgraded &&
    (transaction.productId.endsWith(".lifetime") ||
      Number(transaction.expiresDate) > now)
  );
}

// eslint-disable-next-line require-jsdoc
function validateRequest(data) {
  if (
    !data ||
    !Object.hasOwn(FREE_LIMITS, data.kind) ||
    typeof data.id !== "string" ||
    !/^[a-zA-Z0-9_-]{1,200}$/.test(data.id)
  ) {
    throw new HttpsError("invalid-argument", "Invalid report request.");
  }
  const payload = data.payload;
  if (
    !payload ||
    typeof payload !== "object" ||
    Array.isArray(payload) ||
    Buffer.byteLength(JSON.stringify(payload)) > 24000
  ) {
    throw new HttpsError(
        "invalid-argument",
        "Report data is too large or invalid.",
    );
  }
  // eslint-disable-next-line require-jsdoc
  function visit(value, depth = 0) {
    if (
      depth > 5 ||
      (typeof value === "number" && !Number.isFinite(value)) ||
      (typeof value === "string" && value.length > 2000) ||
      (Array.isArray(value) && value.length > 100)
    ) {
      throw new HttpsError("invalid-argument", "Invalid report data.");
    }
    if (value && typeof value === "object") {
      for (const child of Object.values(value)) visit(child, depth + 1);
    }
  }
  visit(payload);
  if (data.metadata !== undefined) {
    if (
      !data.metadata ||
      typeof data.metadata !== "object" ||
      Array.isArray(data.metadata)
    ) {
      throw new HttpsError("invalid-argument", "Invalid report metadata.");
    }
    for (const [key, value] of Object.entries(data.metadata)) {
      if (["period_start", "period_end"].includes(key)) {
        if (!Number.isFinite(value) || value < 0 || value > 8640000000000000) {
          throw new HttpsError("invalid-argument", "Invalid report dates.");
        }
      } else if (
        !["event_a_id", "event_b_id"].includes(key) ||
        typeof value !== "string" ||
        !/^[a-zA-Z0-9_-]{1,200}$/.test(value)
      ) {
        throw new HttpsError("invalid-argument", "Invalid report metadata.");
      }
    }
  }
  if (
    data.kind === "night" &&
    (!Array.isArray(payload.drinks) ||
      payload.drinks.some(
          (d) =>
            !d ||
          typeof d.name !== "string" ||
          !Number.isInteger(d.quantity) ||
          d.quantity < 0 ||
          d.quantity > 100,
      ))
  ) {
    throw new HttpsError("invalid-argument", "Invalid drinks.");
  }
  if (data.kind === "comparison" && (!payload.eventA || !payload.eventB)) {
    throw new HttpsError("invalid-argument", "Two nights are required.");
  }
  return data;
}

// eslint-disable-next-line require-jsdoc
function reserveQuota(usage, kind, pro, now = Date.now()) {
  const month = new Date(now).toISOString().slice(0, 7);
  const day = new Date(now).toISOString().slice(0, 10);
  const counts = usage.month === month ? {...usage.counts} : {};
  const total = usage.month === month ? usage.total || 0 : 0;
  const daily = usage.day === day ? usage.daily || 0 : 0;
  if (
    daily >= 30 ||
    total >= 300 ||
    (!pro && (counts[kind] || 0) >= FREE_LIMITS[kind])
  ) {
    throw new HttpsError(
        "resource-exhausted",
        "Your report limit has been reached. Please try again after it resets.",
    );
  }
  counts[kind] = (counts[kind] || 0) + 1;
  return {month, day, counts, total: total + 1, daily: daily + 1};
}

module.exports = {activePurchase, validateRequest, reserveQuota};
