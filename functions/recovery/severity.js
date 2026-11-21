// Pure rules for the morning recovery plan: how heavy the night was, which
// safety lines must be shown, and the context the plan is matched against.
// Nothing here calls a model, so it is the part tests can pin down exactly.

const SYMPTOMS = [
  "headache",
  "nausea",
  "wrecked",
  "dizzy",
  "anxious",
  "fine",
];

// Mirrors `highAlcoholAmount` in prompts.js, which must stay untouched: 10
// standard drinks, or 8 when the user is female.
// eslint-disable-next-line require-jsdoc
function veryHeavyAmount(payload) {
  return payload.alcoholDose?.standardDrinks >=
    (payload.userSex === "Female" ? 8 : 10);
}

/**
 * How heavy the night was.
 * @param {object} payload The morning request payload.
 * @return {string} light, moderate, heavy or very_heavy.
 */
function severityOf(payload) {
  if (veryHeavyAmount(payload)) return "very_heavy";
  const dose = payload.alcoholDose || {};
  // Servings with no known alcohol content mean the real total is higher.
  if (dose.missingServings > 0 || dose.standardDrinks >= 6) return "heavy";
  if (dose.standardDrinks >= 3) return "moderate";
  return "light";
}

/**
 * Safety lines the plan must carry regardless of what the model writes.
 * @param {object} payload The morning request payload.
 * @param {string} severity The result of `severityOf`.
 * @return {{dontDrive: boolean, medicalHelp: boolean}} The flags.
 */
function safetyFlags(payload, severity) {
  const symptoms = Array.isArray(payload.symptoms) ? payload.symptoms : [];
  return {
    dontDrive: typeof payload.estimatedBacNow === "number" &&
      payload.estimatedBacNow > 0,
    medicalHelp: severity === "very_heavy" ||
      (severity === "heavy" && symptoms.includes("nausea") &&
        symptoms.includes("dizzy")),
  };
}

/**
 * The facts a plan is matched on.
 * @param {object} payload The morning request payload.
 * @return {object} symptoms, country, timeOfDay and isWorkday.
 */
function nightContext(payload) {
  const country = typeof payload.country === "string" &&
    /^[A-Za-z]{2}$/.test(payload.country) ?
    payload.country.toUpperCase() : "*";
  return {
    symptoms: payload.symptoms,
    country,
    timeOfDay: payload.checkInHour < 11 ? "early" : "late",
    // Calendar weekday: 1 is Sunday, 7 is Saturday.
    isWorkday: payload.weekday >= 2 && payload.weekday <= 6,
  };
}

module.exports = {SYMPTOMS, severityOf, safetyFlags, nightContext};
