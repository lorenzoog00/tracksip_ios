const {test} = require("node:test");
const assert = require("node:assert/strict");
const {parsePlan, ICONS, PLAN_JSON_SCHEMA} = require("./plan");

const lib = (kind, n) => Array.from({length: n}, (_, i) => ({
  id: `${kind[0]}${i + 1}`, name: `${kind} ${i + 1}`, kind, effort: "buy",
}));
const ctx = () => ({
  shortlist: {breakfasts: lib("breakfast", 3), activities: lib("activity", 3)},
});
const plan = (over = {}) => ({
  headline: "Rough one, but you ate late so go easy.",
  rightNow: [
    {icon: "drop.fill", title: "Water first", why: "Only 300ml last night."},
  ],
  breakfast: {
    id: "b1", why: "Salty and easy on a queasy stomach.",
    when: "within the hour",
  },
  fallback: {title: "Plain toast"},
  activities: [{id: "a1", why: "Fresh air after a 4am finish."}],
  skip: {title: "Coffee on empty", why: "Your stomach is already upset."},
  ...over,
});
const parse = (obj, c = ctx()) => parsePlan(JSON.stringify(obj), c);

test("ICONS is the exact SF Symbol list", () => {
  assert.deepEqual(ICONS, [
    "drop.fill", "pills.fill", "cup.and.saucer.fill", "leaf.fill",
    "bed.double.fill", "sun.max.fill", "wind", "fork.knife",
    "bolt.heart.fill", "snowflake", "figure.walk", "moon.zzz.fill",
  ]);
});

test("the schema is plain JSON Schema with the icon enum and no $ref", () => {
  const text = JSON.stringify(PLAN_JSON_SCHEMA);
  assert.ok(!text.includes("$ref"));
  assert.equal(PLAN_JSON_SCHEMA.type, "object");
  assert.deepEqual(
      PLAN_JSON_SCHEMA.properties.rightNow.items.properties.icon.enum, ICONS);
  assert.deepEqual(PLAN_JSON_SCHEMA.required,
      ["headline", "rightNow", "breakfast", "activities"]);
});

test("a valid plan passes through unchanged", () => {
  assert.deepEqual(parse(plan()), plan());
});

test("an id outside the shortlist throws", () => {
  assert.throws(
      () => parse(plan({breakfast: {id: "zzz", why: "x", when: "y"}})),
      /shortlist/);
  assert.throws(() => parse(plan({activities: [{id: "b1", why: "x"}]})),
      /shortlist/);
});

test("a missing breakfast throws", () => {
  const p = plan();
  delete p.breakfast;
  assert.throws(() => parse(p), /breakfast/);
});

test("an item with both or neither of id and new throws", () => {
  const both = {
    id: "b1", new: {name: "X", effort: "cook"}, why: "w", when: "n",
  };
  assert.throws(() => parse(plan({breakfast: both})), /exactly one/);
  assert.throws(() => parse(plan({breakfast: {why: "w", when: "n"}})),
      /exactly one/);
});

test("a first new item is kept", () => {
  const newB = {
    new: {name: "Chilaquiles verdes", effort: "order"}, why: "w", when: "n",
  };
  assert.deepEqual(parse(plan({breakfast: newB})).breakfast, newB);
});

test("a second new item becomes the first unused shortlist item", () => {
  const p = plan({
    breakfast: {
      new: {name: "Mystery bowl", effort: "cook"}, why: "w", when: "n",
    },
    activities: [
      {new: {name: "Sauna", effort: "buy"}, why: "Sweat out the night."},
      {id: "a2", why: "Walk."},
    ],
  });
  const out = parse(p);
  assert.deepEqual(out.breakfast.new, {name: "Mystery bowl", effort: "cook"});
  assert.deepEqual(out.activities.map((a) => a.id), ["a1", "a2"]);
  assert.equal(out.activities[0].why, "Sweat out the night.");
});

test("a second new item with nothing left to swap in is dropped", () => {
  const c = {shortlist: {breakfasts: lib("breakfast", 1), activities: []}};
  const p = plan({
    breakfast: {new: {name: "Mystery bowl", effort: "cook"}, why: "w", when: "n"},
    activities: [{new: {name: "Sauna", effort: "buy"}, why: "a"}],
  });
  // The breakfast took the one new slot, and the shortlist has no activity.
  assert.throws(() => parse(p, c), /activities/);
});

test("a repeated id is dropped", () => {
  const out = parse(plan({
    activities: [{id: "a1", why: "x"}, {id: "a1", why: "y"}],
  }));
  assert.equal(out.activities.length, 1);
});

test("an unknown icon becomes drop.fill", () => {
  const out = parse(plan({
    rightNow: [{icon: "star", title: "Water", why: "Thirsty."}],
  }));
  assert.equal(out.rightNow[0].icon, "drop.fill");
});

test("rightNow and activities are capped", () => {
  const item = (i) => ({icon: "leaf.fill", title: `T${i}`, why: "w"});
  const out = parse(plan({
    rightNow: [1, 2, 3, 4].map(item),
    activities: [
      {id: "a1", why: "x"}, {id: "a2", why: "y"}, {id: "a3", why: "z"},
    ],
  }));
  assert.equal(out.rightNow.length, 3);
  assert.equal(out.activities.length, 2);
});

test("an empty rightNow or activities list throws", () => {
  assert.throws(() => parse(plan({rightNow: []})), /rightNow/);
  assert.throws(() => parse(plan({activities: []})), /activities/);
});

test("a json fence or surrounding prose is tolerated", () => {
  const body = JSON.stringify(plan());
  assert.deepEqual(parsePlan("```json\n" + body + "\n```", ctx()), plan());
  assert.deepEqual(
      parsePlan("Here you go:\n" + body + "\nEnjoy", ctx()), plan());
});

test("text that is not JSON throws", () => {
  assert.throws(() => parsePlan("sorry, no", ctx()), /JSON/);
});

test("long text is cut at a word boundary", () => {
  const words = (n) => Array.from({length: n}, () => "word").join(" ");
  const out = parse(plan({
    headline: words(80),
    rightNow: [{icon: "wind", title: words(30), why: words(60)}],
  }));
  assert.ok(out.headline.length <= 200);
  assert.ok(out.rightNow[0].title.length <= 60);
  assert.ok(out.rightNow[0].why.length <= 140);
  const cut = [out.headline, out.rightNow[0].title, out.rightNow[0].why];
  for (const text of cut) assert.match(text, /word$/, "cut mid-word");
});

test("null or missing fallback and skip become null", () => {
  const p = plan({fallback: null});
  delete p.skip;
  const out = parse(p);
  assert.equal(out.fallback, null);
  assert.equal(out.skip, null);
});
