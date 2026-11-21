const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  historyOf,
  photoSlot,
  libraryItem,
  assemblePlan,
  assertPlannable,
} = require("./morning");

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 10, 20, 15);
const morning = (daysAgo, breakfast, activities) => ({
  type: "morning",
  created_at: NOW - daysAgo * DAY,
  plan: {
    breakfast: {itemId: breakfast},
    activities: activities.map((itemId) => ({itemId})),
  },
});

test("history keeps 30 days of morning picks, and 14 of them apart", () => {
  const history = historyOf([
    morning(3, "b1", ["a1", "a2"]),
    morning(20, "b2", ["a3"]),
    morning(31, "b3", ["a4"]),
    {type: "recovery", created_at: NOW - DAY, report: "Old brief."},
  ], NOW);
  assert.deepEqual([...history[30]].sort(), ["a1", "a2", "a3", "b1", "b2"]);
  assert.deepEqual([...history[14]].sort(), ["a1", "a2", "b1"]);
});

test("history skips a morning record with a broken plan", () => {
  const history = historyOf([
    {type: "morning", created_at: NOW},
    {type: "morning", created_at: NOW, plan: {activities: [null]}},
    morning(1, "b1", []),
  ], NOW);
  assert.deepEqual([...history[30]], ["b1"]);
});

test("the photo counter starts each UTC day at zero", () => {
  assert.deepEqual(photoSlot({day: "2026-11-19", count: 10}, NOW, 10), {
    capped: false, next: {day: "2026-11-20", count: 1},
  });
  assert.deepEqual(photoSlot(undefined, NOW, 10), {
    capped: false, next: {day: "2026-11-20", count: 1},
  });
});

test("the photo counter stops at the daily cap", () => {
  assert.deepEqual(photoSlot({day: "2026-11-20", count: 9}, NOW, 10), {
    capped: false, next: {day: "2026-11-20", count: 10},
  });
  assert.deepEqual(photoSlot({day: "2026-11-20", count: 10}, NOW, 10), {
    capped: true, next: {day: "2026-11-20", count: 10},
  });
});

test("a missing cap counts as reached, so photos are never unbounded", () => {
  assert.equal(photoSlot(undefined, NOW, undefined).capped, true);
  assert.equal(photoSlot(undefined, NOW, NaN).capped, true);
});

const ctx = (over = {}) => ({
  payload: {},
  severity: "heavy",
  safety: {dontDrive: true, medicalHelp: false},
  symptoms: ["headache", "nausea"],
  country: "MX",
  timeOfDay: "early",
  isWorkday: true,
  shortlist: {
    breakfasts: [
      {id: "b1", name: "Chilaquiles", photoUrl: "https://x/b1.jpg"},
      {id: "b2", name: "Molletes", photoUrl: "https://x/b2.jpg"},
    ],
    activities: [
      {id: "a1", name: "Short walk", photoUrl: "https://x/a1.jpg"},
      {id: "a2", name: "Cold shower", photoUrl: "https://x/a2.jpg"},
    ],
  },
  ...over,
});

test("a shortlist missing either kind is refused before anything is spent", () => {
  // parsePlan needs a breakfast and an activity, and the model may invent
  // only one item, so an empty kind can fail every attempt.
  const full = ctx().shortlist;
  for (const shortlist of [
    {breakfasts: [], activities: []},
    {breakfasts: [], activities: full.activities},
    {breakfasts: full.breakfasts, activities: []},
  ]) {
    assert.throws(
        () => assertPlannable(ctx({shortlist})),
        (e) => e.code === "failed-precondition",
    );
  }
  assert.doesNotThrow(() => assertPlannable(ctx()));
});

test("a new item is labeled from the night and waits for its photo", () => {
  const item = libraryItem(
      {name: "Tacos de canasta", effort: "buy", kind: "breakfast"},
      ctx(),
      {planPath: "users/alice/night_recoveries/e1", now: NOW, capped: false},
  );
  assert.deepEqual(item, {
    name: "Tacos de canasta",
    title: "Tacos de canasta",
    kind: "breakfast",
    countries: ["MX"],
    goodFor: ["headache", "nausea"],
    avoidWhen: [],
    severities: ["heavy"],
    effort: "buy",
    timeOfDay: ["early"],
    normalizedName: "tacos de canasta",
    photoUrl: null,
    photoStatus: "generating",
    review: "pending",
    createdAt: NOW,
    pendingPlanPaths: ["users/alice/night_recoveries/e1"],
  });
});

test("a capped item says so, and feeling fine is not a label", () => {
  const item = libraryItem(
      {name: "Stretch", effort: "none", kind: "activity"},
      ctx({symptoms: ["fine"], country: "*", timeOfDay: "late"}),
      {planPath: "users/bob/night_recoveries/e2", now: NOW, capped: true},
  );
  assert.equal(item.photoStatus, "capped");
  assert.equal(item.kind, "activity");
  assert.deepEqual(item.goodFor, []);
  assert.deepEqual(item.countries, ["*"]);
  assert.deepEqual(item.timeOfDay, ["late"]);
});

const parsed = (over = {}) => ({
  headline: "Rough one.",
  rightNow: [{icon: "drop.fill", title: "Water", why: "Dry night."}],
  breakfast: {id: "b2", why: "Easy on the stomach.", when: "soon"},
  fallback: {title: "Toast"},
  activities: [{id: "a1", why: "Air."}],
  skip: null,
  ...over,
});

test("picks get their name and photo from the library", () => {
  assert.deepEqual(assemblePlan(parsed(), ctx(), null), {
    symptoms: ["headache", "nausea"],
    severity: "heavy",
    safety: {dontDrive: true, medicalHelp: false},
    plan: {
      headline: "Rough one.",
      rightNow: [{icon: "drop.fill", title: "Water", why: "Dry night."}],
      breakfast: {
        itemId: "b2", name: "Molletes", why: "Easy on the stomach.",
        when: "soon", photoUrl: "https://x/b2.jpg",
      },
      fallback: {title: "Toast"},
      activities: [{
        itemId: "a1", name: "Short walk", why: "Air.",
        photoUrl: "https://x/a1.jpg",
      }],
      skip: null,
    },
  });
});

test("a pick's name is the item's display title, not its photo subject", () => {
  const titled = ctx();
  titled.shortlist.breakfasts[1] = {
    ...titled.shortlist.breakfasts[1],
    name: "Molletes with beans, melted cheese and pico de gallo",
    title: "Molletes with pico de gallo",
  };
  titled.shortlist.activities[0] = {
    ...titled.shortlist.activities[0],
    name: "A quiet tree-lined street at sunrise for a slow walk",
    title: "Slow walk around the block",
  };
  const out = assemblePlan(parsed(), titled, null);
  assert.equal(out.plan.breakfast.name, "Molletes with pico de gallo");
  assert.equal(out.plan.activities[0].name, "Slow walk around the block");
  const added = assemblePlan(parsed({
    breakfast: {new: {name: "tacos", effort: "buy"}, why: "W", when: "now"},
  }), ctx(), {
    id: "new-1", name: "Tacos de canasta with salsa verde", title: "Tacos de canasta",
    photoUrl: null,
  });
  assert.equal(added.plan.breakfast.name, "Tacos de canasta");
});

test("the new pick becomes the item it was saved as", () => {
  const out = assemblePlan(parsed({
    breakfast: {new: {name: "tacos", effort: "buy"}, why: "W", when: "now"},
  }), ctx(), {id: "new-1", name: "Tacos de canasta", photoUrl: null});
  assert.deepEqual(out.plan.breakfast, {
    itemId: "new-1", name: "Tacos de canasta", why: "W", when: "now",
    photoUrl: null,
  });
});

test("a new activity that turns out to be one already picked is dropped", () => {
  const out = assemblePlan(parsed({
    activities: [
      {id: "a1", why: "Air."},
      {new: {name: "short walk", effort: "none"}, why: "Again."},
    ],
  }), ctx(), {id: "a1", name: "Short walk", photoUrl: "https://x/a1.jpg"});
  assert.deepEqual(out.plan.activities.map((a) => a.why), ["Air."]);
});
