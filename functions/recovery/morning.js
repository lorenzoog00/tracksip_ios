// Loads what a morning plan is built from, and turns the model's parsed
// answer into the stored plan: library names and photos in, at most one new
// library item out, under the app-wide daily photo cap.

const {HttpsError} = require("firebase-functions/v2/https");
const {severityOf, safetyFlags, nightContext} = require("./severity");
const {normalizeName, shortlist, findDuplicate} = require("./library");

const DAY_MS = 24 * 60 * 60 * 1000;
const LIBRARY_TTL_MS = 10 * 60 * 1000;

// Approved items change only when the owner reviews photos, so one read per
// instance every 10 minutes is enough.
let libraryCache = null;

/** Forgets the cached library, for tests that rewrite it. */
function resetLibraryCache() {
  libraryCache = null;
}

/**
 * Approved library items, each with its `id`.
 * @param {object} db Firestore.
 * @param {number} now Epoch ms.
 * @return {Promise<object[]>} The items.
 */
async function loadLibrary(db, now) {
  if (libraryCache && now - libraryCache.at < LIBRARY_TTL_MS) {
    return libraryCache.items;
  }
  const snapshot = await db.collection("recovery_library")
      .where("review", "==", "approved").get();
  const items = snapshot.docs.map((doc) => ({...doc.data(), id: doc.id}));
  libraryCache = {at: now, items};
  return items;
}

/**
 * Library ids this user's morning plans picked, in the shortlist's windows.
 * @param {object[]} records The user's night_recoveries data.
 * @param {number} now Epoch ms.
 * @return {{30: Set<string>, 14: Set<string>}} Ids seen per window.
 */
function historyOf(records, now) {
  const history = {30: new Set(), 14: new Set()};
  const within = (record, days) => record.created_at >= now - days * DAY_MS;
  for (const record of records) {
    if (record.type !== "morning" || !within(record, 30)) continue;
    const activities = record.plan?.activities;
    const picks = [
      record.plan?.breakfast,
      ...(Array.isArray(activities) ? activities : []),
    ];
    for (const pick of picks) {
      if (typeof pick?.itemId !== "string") continue;
      history[30].add(pick.itemId);
      if (within(record, 14)) history[14].add(pick.itemId);
    }
  }
  return history;
}

/**
 * Everything the prompt, the parser and `finalizePlan` need for one morning.
 * @param {object} args `{db, uid, payload, now, rng}`.
 * @return {Promise<object>} payload, severity, safety, symptoms, country,
 *     timeOfDay, isWorkday, library and shortlist.
 */
async function loadMorningContext({
  db, uid, payload, now = Date.now(), rng = Math.random,
}) {
  const severity = severityOf(payload);
  const night = nightContext(payload);
  // A single-field range, so no composite index: the type is checked here.
  const [library, recent] = await Promise.all([
    loadLibrary(db, now),
    db.collection(`users/${uid}/night_recoveries`)
        .where("created_at", ">=", now - 30 * DAY_MS).get(),
  ]);
  const history = historyOf(recent.docs.map((doc) => doc.data()), now);
  return {
    payload,
    severity,
    safety: safetyFlags(payload, severity),
    ...night,
    library,
    shortlist: shortlist(library, {...night, severity}, history, rng),
  };
}

/**
 * Refuses a morning whose shortlist lacks breakfasts or activities. A plan
 * needs both and the model may invent only one item, so such a request can
 * fail every attempt; it is refused before any quota is reserved.
 * @param {object} ctx The morning context.
 */
function assertPlannable(ctx) {
  const {breakfasts, activities} = ctx.shortlist;
  if (breakfasts.length === 0 || activities.length === 0) {
    throw new HttpsError(
        "failed-precondition",
        "A recovery plan isn't available for this check-in yet.",
    );
  }
}

/**
 * Takes a slot on the app-wide daily photo counter, if one is left.
 * @param {object|undefined} counter `recovery_meta/photos`: `{day, count}`.
 * @param {number} now Epoch ms.
 * @param {number} dailyCap Photos allowed per UTC day.
 * @return {{capped: boolean, next: {day: string, count: number}}} Whether
 *     the cap is reached, and the counter to store if it is not.
 */
function photoSlot(counter, now, dailyCap) {
  const day = new Date(now).toISOString().slice(0, 10);
  const used = counter?.day === day ? counter.count || 0 : 0;
  // "Not under" rather than "at or over", so a missing or non-numeric cap
  // counts as reached: a cost guard fails closed.
  const capped = !(used < dailyCap);
  return {capped, next: {day, count: capped ? used : used + 1}};
}

/**
 * The library doc for a proposal the model made, labeled from this night.
 * @param {object} proposal `{name, effort, kind}`.
 * @param {object} ctx The morning context.
 * @param {object} meta `{planPath, now, capped}`.
 * @return {object} The `recovery_library` document.
 */
function libraryItem({name, effort, kind}, ctx, {planPath, now, capped}) {
  return {
    // The model's name is short already (parsePlan clips it), so it is both
    // the photo subject and the title users read until a review renames it.
    name,
    title: name,
    kind,
    countries: [ctx.country],
    goodFor: ctx.symptoms.filter((symptom) => symptom !== "fine"),
    avoidWhen: [],
    severities: [ctx.severity],
    effort,
    timeOfDay: [ctx.timeOfDay],
    normalizedName: normalizeName(name),
    photoUrl: null,
    photoStatus: capped ? "capped" : "generating",
    review: "pending",
    createdAt: now,
    // The photo trigger fills this plan's photo by `itemId` when it is done.
    pendingPlanPaths: [planPath],
  };
}

/**
 * What the app shows as an item's name: its short display title, or the
 * detailed name (the photo subject) for an item saved before titles.
 * @param {object} item A library item.
 * @return {string} The display name.
 */
function displayName(item) {
  return item.title ?? item.name;
}

/**
 * The stored plan body, with names and photos from the library. A pick's
 * `name` is the item's display title; the app shows it as is.
 * @param {object} parsed `parsePlan` output.
 * @param {object} ctx The morning context.
 * @param {object|null} added `{id, name, title, photoUrl}` for the one `new`
 *     pick.
 * @return {object} symptoms, severity, safety and plan.
 */
function assemblePlan(parsed, ctx, added) {
  const known = new Map(
      [...ctx.shortlist.breakfasts, ...ctx.shortlist.activities]
          .map((item) => [item.id, item]),
  );
  const itemOf = (pick) => pick.new ? added : known.get(pick.id);
  const breakfast = itemOf(parsed.breakfast);
  const activities = [];
  for (const pick of parsed.activities) {
    const item = itemOf(pick);
    // A proposal can turn out to be an item that is already in the plan.
    if (activities.some((activity) => activity.itemId === item.id)) continue;
    activities.push({
      itemId: item.id, name: displayName(item), why: pick.why,
      photoUrl: item.photoUrl ?? null,
    });
  }
  return {
    symptoms: ctx.symptoms,
    severity: ctx.severity,
    safety: ctx.safety,
    plan: {
      headline: parsed.headline,
      rightNow: parsed.rightNow,
      breakfast: {
        itemId: breakfast.id,
        name: displayName(breakfast),
        why: parsed.breakfast.why,
        when: parsed.breakfast.when,
        photoUrl: breakfast.photoUrl ?? null,
      },
      fallback: parsed.fallback,
      activities,
      skip: parsed.skip,
    },
  };
}

/**
 * Finds or creates the library item for the model's one proposal. The name
 * is matched against every unrejected item, pending ones included, so a
 * retried or repeated proposal does not pay for a second photo.
 * @param {object} db Firestore.
 * @param {object} proposal `{name, effort, kind}`.
 * @param {object} ctx The morning context.
 * @param {object} meta `{planPath, now, dailyCap}`.
 * @return {Promise<object>} `{id, name, title, photoUrl}` for the plan.
 */
function addToLibrary(db, proposal, ctx, {planPath, now, dailyCap}) {
  const library = db.collection("recovery_library");
  const counter = db.doc("recovery_meta/photos");
  const normalizedName = normalizeName(proposal.name);
  return db.runTransaction(async (tx) => {
    const named = await tx.get(
        library.where("normalizedName", "==", normalizedName));
    const candidates = [
      ...named.docs.map((doc) => ({...doc.data(), id: doc.id})),
      ...ctx.library,
    ].filter((item) => item.kind === proposal.kind);
    const existing = findDuplicate(candidates, proposal.name, ctx.country);
    if (existing) {
      // An unreviewed photo is shown only on the plan that asked for it.
      return {
        id: existing.id,
        name: existing.name,
        title: displayName(existing),
        photoUrl: existing.review === "approved" ?
          existing.photoUrl ?? null : null,
      };
    }
    const slot = photoSlot((await tx.get(counter)).data(), now, dailyCap);
    const ref = library.doc();
    tx.set(ref, libraryItem(proposal, ctx, {
      planPath, now, capped: slot.capped,
    }));
    if (!slot.capped) tx.set(counter, slot.next);
    return {
      id: ref.id, name: proposal.name, title: proposal.name, photoUrl: null,
    };
  });
}

/**
 * Turns the parsed answer into the stored plan body, adding the model's one
 * proposal, if it made one, to the library first.
 * @param {object} args `{db, uid, eventId, parsed, ctx, now, dailyCap}`.
 * @return {Promise<object>} symptoms, severity, safety and plan;
 *     `generateReport` adds type, version and created_at.
 */
async function finalizePlan({
  db, uid, eventId, parsed, ctx, now = Date.now(), dailyCap,
}) {
  const picks = [
    {...parsed.breakfast, kind: "breakfast"},
    ...parsed.activities.map((pick) => ({...pick, kind: "activity"})),
  ];
  const proposed = picks.find((pick) => pick.new);
  const added = proposed ?
    await addToLibrary(db, {...proposed.new, kind: proposed.kind}, ctx, {
      planPath: `users/${uid}/night_recoveries/${eventId}`, now, dailyCap,
    }) :
    null;
  return assemblePlan(parsed, ctx, added);
}

module.exports = {
  loadMorningContext,
  assertPlannable,
  finalizePlan,
  resetLibraryCache,
  historyOf,
  photoSlot,
  libraryItem,
  assemblePlan,
};
