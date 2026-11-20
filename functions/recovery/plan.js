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

const text = {type: "string"};
const pick = {
  type: "object",
  properties: {
    id: text,
    new: {
      type: "object",
      properties: {name: text, effort: {type: "string", enum: EFFORTS}},
      required: ["name", "effort"],
    },
    why: text,
  },
  required: ["why"],
};

// What Task 4 hands the model. Exactly one of id/new is enforced by
// `parsePlan`, because plain JSON Schema cannot say it without `oneOf`.
const PLAN_JSON_SCHEMA = {
  type: "object",
  properties: {
    headline: text,
    rightNow: {
      type: "array",
      maxItems: 3,
      items: {
        type: "object",
        properties: {
          icon: {type: "string", enum: ICONS},
          title: text,
          why: text,
        },
        required: ["icon", "title", "why"],
      },
    },
    breakfast: {
      ...pick,
      properties: {...pick.properties, when: text},
      required: ["why", "when"],
    },
    fallback: {
      type: "object", properties: {title: text}, required: ["title"],
    },
    activities: {type: "array", maxItems: 2, items: pick},
    skip: {
      type: "object",
      properties: {title: text, why: text},
      required: ["title", "why"],
    },
  },
  required: ["headline", "rightNow", "breakfast", "activities"],
};

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
 * Requires a non-empty string and clips it.
 * @param {*} value The candidate.
 * @param {number} max The longest result allowed.
 * @param {string} label What it is, for the error.
 * @return {string} The clipped text.
 */
function str(value, max, label) {
  if (typeof value !== "string" || !value.trim()) {
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
  const used = new Set();
  let newUsed = false;

  // Resolves one pick against its pool. Returns null when it is a repeat or
  // a spare `new` with nothing to swap in, so the caller can drop it.
  const resolve = (entry, pool, label) => {
    if (entry === null || typeof entry !== "object") {
      throw new Error(`plan ${label} is missing`);
    }
    const hasId = entry.id !== undefined && entry.id !== null;
    const hasNew = entry.new !== undefined && entry.new !== null;
    if (hasId === hasNew) {
      throw new Error(`plan ${label} needs exactly one of id or new`);
    }
    if (hasId) {
      if (!pool.some((item) => item.id === entry.id)) {
        throw new Error(`plan ${label} id is not in the shortlist`);
      }
      if (used.has(entry.id)) return null;
      used.add(entry.id);
      return {id: entry.id};
    }
    if (!newUsed) {
      newUsed = true;
      return {new: {
        name: str(entry.new.name, MAX.name, `${label} name`),
        effort: EFFORTS.includes(entry.new.effort) ? entry.new.effort : "buy",
      }};
    }
    const spare = pool.find((item) => !used.has(item.id));
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
  const breakfast = {
    ...bPick,
    why: str(data.breakfast.why, MAX.why, "breakfast why"),
    when: str(data.breakfast.when, MAX.when, "breakfast when"),
  };

  const activitiesIn = Array.isArray(data.activities) ? data.activities : [];
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

  const fallback = data.fallback && typeof data.fallback.title === "string" ?
    {title: clip(data.fallback.title, MAX.title)} : null;
  const skip = data.skip && typeof data.skip.title === "string" &&
    typeof data.skip.why === "string" ?
    {
      title: clip(data.skip.title, MAX.title),
      why: clip(data.skip.why, MAX.why),
    } : null;

  return {
    headline: str(data.headline, MAX.headline, "headline"),
    rightNow, breakfast, fallback, activities, skip,
  };
}

module.exports = {ICONS, PLAN_JSON_SCHEMA, parsePlan};
