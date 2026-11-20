// Picks which recovery-library items a plan may choose from, and spots
// duplicates by name. Pure functions: callers load the items and the user's
// history from Firestore.

const MAX_BREAKFASTS = 12;
const MAX_ACTIVITIES = 10;
const MIN_PER_KIND = 3;

/**
 * Lowercase, accent-free, punctuation-free form of a name, for comparing.
 * @param {string} name The display name.
 * @return {string} The normalized name.
 */
function normalizeName(name) {
  return String(name || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9\s]/g, " ")
      .replace(/\s+/g, " ")
      .trim()
      .replace(/^(a|an|the) /, "");
}

// eslint-disable-next-line require-jsdoc
function inCountry(item, country) {
  const countries = item.countries || [];
  return countries.includes("*") || countries.includes(country);
}

// eslint-disable-next-line require-jsdoc
function isEligible(item, ctx) {
  const symptoms = ctx.symptoms || [];
  return item.review === "approved" &&
    item.photoStatus === "ready" &&
    inCountry(item, ctx.country) &&
    !(item.avoidWhen || []).some((s) => symptoms.includes(s)) &&
    (item.severities || []).includes(ctx.severity) &&
    (item.timeOfDay || []).includes(ctx.timeOfDay);
}

// Drop what the user already got: 30 days first, then 14, then nothing, as
// soon as a window leaves at least MIN_PER_KIND items.
// eslint-disable-next-line require-jsdoc
function applyHistory(items, historyByWindow) {
  for (const days of [30, 14]) {
    const seen = historyByWindow?.[days];
    if (!seen) continue;
    const left = items.filter((i) => !seen.has(i.id));
    if (left.length >= MIN_PER_KIND) return left;
  }
  return items;
}

// eslint-disable-next-line require-jsdoc
function rank(items, ctx, rng) {
  const symptoms = ctx.symptoms || [];
  const scored = items.map((item) => ({
    item,
    fit: (item.goodFor || []).filter((s) => symptoms.includes(s)).length,
    easy: ctx.isWorkday && item.kind === "breakfast" &&
      (item.effort === "buy" || item.effort === "none") ? 1 : 0,
    tie: rng(),
  }));
  scored.sort((a, b) =>
    b.fit - a.fit || b.easy - a.easy || a.tie - b.tie);
  return scored.map((s) => s.item);
}

/**
 * The library items one user's morning plan may pick from.
 * @param {object[]} items Library items, each with its `id`.
 * @param {object} ctx country, symptoms, severity, timeOfDay, isWorkday.
 * @param {object} historyByWindow {30: Set, 14: Set} of ids already shown.
 * @param {function(): number} rng Returns [0, 1); breaks ties only.
 * @return {{breakfasts: object[], activities: object[]}} The shortlist.
 */
function shortlist(items, ctx, historyByWindow, rng = Math.random) {
  const eligible = items.filter((i) => isEligible(i, ctx));
  const pick = (kind, cap) =>
    rank(applyHistory(eligible.filter((i) => i.kind === kind),
        historyByWindow), ctx, rng).slice(0, cap);
  return {
    breakfasts: pick("breakfast", MAX_BREAKFASTS),
    activities: pick("activity", MAX_ACTIVITIES),
  };
}

/**
 * An existing, non-rejected item with the same name for this country.
 * @param {object[]} items Library items.
 * @param {string} name The candidate name.
 * @param {string} country Country code or "*".
 * @return {object|null} The matching item, if any.
 */
function findDuplicate(items, name, country) {
  const wanted = normalizeName(name);
  return items.find((i) =>
    i.review !== "rejected" &&
    inCountry(i, country) &&
    (i.normalizedName ?? normalizeName(i.name)) === wanted) || null;
}

module.exports = {normalizeName, shortlist, findDuplicate};
