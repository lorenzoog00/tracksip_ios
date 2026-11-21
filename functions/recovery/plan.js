// Validates the JSON Claude returns for a morning plan. The model picks from a
// shortlist, so anything it invents that the app cannot render is repaired or
// refused here rather than shown.

const ICONS = [
  "drop.fill", "pills.fill", "cup.and.saucer.fill", "leaf.fill",
  "bed.double.fill", "sun.max.fill", "wind", "fork.knife",
  "bolt.heart.fill", "snowflake", "figure.walk", "moon.zzz.fill",
];
const EFFORTS = ["cook", "buy", "order", "none"];
const FALLBACK_ICON = "drop.fill";
const MAX = {headline: 200, title: 60, why: 140, when: 60, name: 60};

// Drinks that never belong in a recovery plan, matched as whole words (the
// "\\b" is a regex word boundary, not a backspace). A proposed item that
// names one is swapped for a shortlist item. The seed test holds the starter
// library to the same list.
const ALCOHOL = new RegExp("\\b(" + [
  "beers?", "cervezas?", "chelas?", "micheladas?", "caguamas?", "mimosas?",
  "bloody marys?", "tequilas?", "mezcal", "vodka", "rum", "whiske?y",
  "bourbon", "wines?", "liquor", "shots?", "hair of the dog", "cocktails?",
  "champagne", "prosecco", "sangria", "gin", "brandy", "pulque", "booze",
].join("|") + ")\\b", "i");

const text = {type: "string"};
// Structured outputs needs every object closed, so each one lists its keys.
const object = (properties, required) =>
  ({type: "object", properties, required, additionalProperties: false});
const pickProperties = {
  id: text,
  new: object(
      {name: text, effort: {type: "string", enum: EFFORTS}},
      ["name", "effort"],
  ),
  why: text,
};

// What index.js hands the model as its structured output format. Exactly one
// of id/new is enforced by `parsePlan`, because plain JSON Schema cannot say
// it without `oneOf`. Structured outputs has no array length limits, so the
// counts are in the descriptions and `parsePlan` cuts any extra.
const PLAN_JSON_SCHEMA = object({
  headline: text,
  rightNow: {
    type: "array",
    description: "1 to 3 items.",
    items: object({
      icon: {type: "string", enum: ICONS},
      title: text,
      why: text,
    }, ["icon", "title", "why"]),
  },
  breakfast: object({...pickProperties, when: text}, ["why", "when"]),
  fallback: object({title: text}, ["title"]),
  activities: {
    type: "array",
    description: "1 or 2 items.",
    items: object(pickProperties, ["why"]),
  },
  skip: object({title: text, why: text}, ["title", "why"]),
}, ["headline", "rightNow", "breakfast", "activities"]);

/**
 * Cuts text to `max` characters at a word boundary.
 * @param {string} value The text.
 * @param {number} max The longest result allowed.
 * @return {string} The text, shortened if it was over.
 */
function clip(value, max) {
  const clean = value.replace(/\s+/g, " ").trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max);
  const space = cut.lastIndexOf(" ");
  return (space > 0 ? cut.slice(0, space) : cut).trim();
}

/**
 * Whether a value is a string with something other than whitespace in it.
 * @param {*} value The candidate.
 * @return {boolean} True for non-blank text.
 */
function filled(value) {
  return typeof value === "string" && value.trim() !== "";
}

/**
 * Requires a non-empty string and clips it.
 * @param {*} value The candidate.
 * @param {number} max The longest result allowed.
 * @param {string} label What it is, for the error.
 * @return {string} The clipped text.
 */
function str(value, max, label) {
  if (!filled(value)) {
    throw new Error(`plan ${label} is missing`);
  }
  return clip(value, max);
}

/**
 * Pulls the JSON object out of the model's text.
 * @param {string} raw The model output.
 * @return {object} The parsed object.
 */
function extractJson(raw) {
  const body = String(raw);
  const start = body.indexOf("{");
  const end = body.lastIndexOf("}");
  if (start < 0 || end < start) throw new Error("plan has no JSON object");
  let parsed;
  try {
    parsed = JSON.parse(body.slice(start, end + 1));
  } catch {
    throw new Error("plan is not valid JSON");
  }
  if (parsed === null || typeof parsed !== "object" ||
      Array.isArray(parsed)) {
    throw new Error("plan is not a JSON object");
  }
  return parsed;
}

/**
 * Validates and repairs the model's plan.
 * @param {string} raw The model output.
 * @param {object} ctx Holds `shortlist: {breakfasts, activities}`.
 * @return {object} The plan: headline, rightNow, breakfast, fallback,
 *     activities and skip. Picks keep `{id}` or `{new: {name, effort}}`.
 */
function parsePlan(raw, ctx) {
  const data = extractJson(raw);
  const {breakfasts, activities: activityPool} = ctx.shortlist;
  const activitiesIn = Array.isArray(data.activities) ? data.activities : [];
  const used = new Set();
  let newUsed = false;
  const inPool = (pool, id) => pool.some((item) => item.id === id);
  // Shortlist ids the model picked in the right slot. A repair takes an item
  // it did not pick first, so swapping one pick never knocks out a later one
  // as a repeat.
  const named = new Set([
    ...[data.breakfast].filter((entry) => inPool(breakfasts, entry?.id)),
    ...activitiesIn.filter((entry) => inPool(activityPool, entry?.id)),
  ].map((entry) => entry.id));
  const spareIn = (pool) =>
    pool.find((item) => !used.has(item.id) && !named.has(item.id)) ??
    pool.find((item) => !used.has(item.id));

  // Resolves one pick against its pool. A pick the app cannot show as asked
  // (an id outside this kind's shortlist, a second `new`, or a `new` that
  // names a drink) is repaired with the first unused shortlist item of the
  // same kind, so a near-miss reply does not cost the user an attempt.
  // Returns null when it is a repeat or there is nothing left to swap in,
  // so the caller can drop it.
  const resolve = (entry, pool, label) => {
    if (entry === null || typeof entry !== "object") {
      throw new Error(`plan ${label} is missing`);
    }
    const hasId = entry.id !== undefined && entry.id !== null;
    const hasNew = entry.new !== undefined && entry.new !== null;
    if (hasId === hasNew) {
      throw new Error(`plan ${label} needs exactly one of id or new`);
    }
    if (hasId && inPool(pool, entry.id)) {
      if (used.has(entry.id)) return null;
      used.add(entry.id);
      return {id: entry.id};
    }
    if (hasNew && !newUsed) {
      const name = str(entry.new.name, MAX.name, `${label} name`);
      if (!ALCOHOL.test(name)) {
        newUsed = true;
        return {new: {
          name,
          effort: EFFORTS.includes(entry.new.effort) ?
            entry.new.effort : "buy",
        }};
      }
    }
    const spare = spareIn(pool);
    if (!spare) return null;
    used.add(spare.id);
    return {id: spare.id};
  };

  const rightNowIn = Array.isArray(data.rightNow) ? data.rightNow : [];
  if (rightNowIn.length === 0) throw new Error("plan rightNow is empty");
  const rightNow = rightNowIn.slice(0, 3).map((entry) => ({
    icon: ICONS.includes(entry?.icon) ? entry.icon : FALLBACK_ICON,
    title: str(entry?.title, MAX.title, "rightNow title"),
    why: str(entry?.why, MAX.why, "rightNow why"),
  }));

  const bPick = resolve(data.breakfast, breakfasts, "breakfast");
  if (!bPick) throw new Error("plan breakfast could not be resolved");
  // A plan without a time is still worth showing; losing the whole plan to
  // it, and a free attempt with it, is not.
  const breakfast = {
    ...bPick,
    why: str(data.breakfast.why, MAX.why, "breakfast why"),
    when: filled(data.breakfast.when) ?
      clip(data.breakfast.when, MAX.when) : "soon",
  };

  const activities = [];
  for (const entry of activitiesIn) {
    if (activities.length === 2) break;
    const picked = resolve(entry, activityPool, "activity");
    if (picked) {
      activities.push({
        ...picked, why: str(entry.why, MAX.why, "activity why"),
      });
    }
  }
  if (activities.length === 0) throw new Error("plan activities is empty");

  // Optional lines: a blank one is left out rather than shown empty.
  const fallback = filled(data.fallback?.title) ?
    {title: clip(data.fallback.title, MAX.title)} : null;
  const skip = filled(data.skip?.title) && filled(data.skip.why) ?
    {
      title: clip(data.skip.title, MAX.title),
      why: clip(data.skip.why, MAX.why),
    } : null;

  return {
    headline: str(data.headline, MAX.headline, "headline"),
    rightNow, breakfast, fallback, activities, skip,
  };
}

module.exports = {ICONS, ALCOHOL, PLAN_JSON_SCHEMA, parsePlan};
