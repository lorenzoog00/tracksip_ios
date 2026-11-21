const {test} = require("node:test");
const assert = require("node:assert/strict");
const seed = require("./library-seed.json");
const {normalizeName, shortlist} = require("./library");
const {SYMPTOMS} = require("./severity");
const {ALCOHOL} = require("./plan");

const SEVERITIES = ["light", "moderate", "heavy", "very_heavy"];
const EFFORTS = ["cook", "buy", "order", "none"];
const TIMES = ["early", "late"];
// `name` is the detailed photo subject; `title` is the short line users read
// in their plan.
const FIELDS = [
  "id", "title", "name", "kind", "countries", "goodFor", "avoidWhen",
  "severities", "effort", "timeOfDay", "normalizedName",
];
const words = (text) => text.trim().split(/\s+/).length;
const PREFIX = {"MX": "mx-", "US": "us-", "*": "x-"};
const own = (country, kind) => seed.filter((e) =>
  e.countries[0] === country && (!kind || e.kind === kind));

test("every entry has exactly the schema fields with valid values", () => {
  for (const e of seed) {
    assert.deepEqual(Object.keys(e).sort(), [...FIELDS].sort(), e.id);
    assert.match(e.id, /^[a-z0-9]+(-[a-z0-9]+)*$/, e.id);
    assert.ok(e.name.length > 3 && e.name.length <= 70, e.id);
    assert.ok(["breakfast", "activity"].includes(e.kind), e.id);
    assert.equal(e.countries.length, 1, e.id);
    assert.ok(["MX", "US", "*"].includes(e.countries[0]), e.id);
    assert.ok(e.id.startsWith(PREFIX[e.countries[0]]), e.id);
    for (const list of [e.goodFor, e.avoidWhen]) {
      assert.ok(Array.isArray(list), e.id);
      for (const s of list) assert.ok(SYMPTOMS.includes(s), `${e.id} ${s}`);
    }
    assert.ok(e.severities.length > 0, e.id);
    for (const s of e.severities) assert.ok(SEVERITIES.includes(s), e.id);
    assert.ok(EFFORTS.includes(e.effort), e.id);
    assert.ok(e.timeOfDay.length > 0, e.id);
    for (const t of e.timeOfDay) assert.ok(TIMES.includes(t), e.id);
    assert.equal(e.normalizedName, normalizeName(e.name), e.id);
  }
});

test("ids are unique and normalized names are unique within a country", () => {
  assert.equal(new Set(seed.map((e) => e.id)).size, seed.length);
  for (const c of ["MX", "US", "*"]) {
    const names = own(c).map((e) => e.normalizedName);
    assert.equal(new Set(names).size, names.length, c);
  }
  // A country-specific item must not repeat a shared dish either.
  const shared = new Set(own("*").map((e) => e.normalizedName));
  for (const e of seed.filter((x) => x.countries[0] !== "*")) {
    assert.ok(!shared.has(e.normalizedName), e.id);
  }
});

test("every item has a short title that says what to eat or do", () => {
  for (const e of seed) {
    assert.equal(typeof e.title, "string", e.id);
    assert.equal(e.title, e.title.trim(), e.id);
    assert.ok(e.title.length > 3 && e.title.length <= 60, e.id);
    assert.ok(words(e.title) <= 8, `${e.id} title is over 8 words`);
    assert.ok(!/(^|[^a-z])your?([^a-z]|$)/i.test(e.title),
        `${e.id} title talks to the user`);
  }
});

test("titles are unique within what one country is shown", () => {
  // A country sees its own items and the shared ones, so a title must not
  // repeat across that whole set.
  for (const c of ["MX", "US"]) {
    const titles = [...own(c), ...own("*")]
        .map((e) => normalizeName(e.title));
    const seen = new Set();
    for (const t of titles) {
      assert.ok(!seen.has(t), `${c} repeats the title "${t}"`);
      seen.add(t);
    }
  }
});

test("no item names or titles a drink", () => {
  // Whole words, so "ginger" or "swine" never trip "gin" or "wine". "\\b"
  // is a regex word boundary; a bare "\b" in a string is a backspace.
  const liquor = new RegExp("\\b(" + [
    "beers?", "cervezas?", "micheladas?", "mimosas?", "bloody marys?",
    "tequilas?", "mezcal", "vodka", "rum", "whiske?y", "bourbon", "wines?",
    "liquor", "shots?", "hair of the dog",
  ].join("|") + ")\\b", "i");
  assert.ok(liquor.test("a michelada") && !liquor.test("ginger shower"));
  for (const e of seed) {
    for (const text of [e.name, e.title]) {
      assert.ok(!liquor.test(text), `${e.id}: ${text}`);
      assert.ok(!ALCOHOL.test(text), `${e.id}: ${text}`);
    }
  }
});

test("content rules hold", () => {
  const banned = new RegExp([
    "michelada", "hair of the dog", "beer", "wine", "tequila", "vodka",
    "whiskey", "cocktail", "mimosa", "bloody mary", "electrolit",
    "pedialyte", "gatorade", "suero", "sober", "coca", "starbucks",
    "mcdonald", "red bull", "advil", "tylenol",
  ].join("|"), "i");
  const exercise = new RegExp([
    "(^|[^a-z])run", "gym", "workout", "weights", "hiit", "cycling", "bike ride",
    "stationary bike", "swim laps", "(^|[^a-z])jog", "pilates", "jump rope",
    "(^|[^a-z])spin([^a-z]|$)", "pickup soccer", "treadmill", "(^|[^a-z])hik(e|ing)", "stairs",
    "yoga", "sun salutation",
  ].join("|"), "i");
  const greasy = new RegExp([
    "(^|[^a-z])fried", "greasy", "bacon", "sausage", "chorizo", "birria", "menudo",
    "spicy", "chili", "hash browns", "biscuits and gravy", "(^|[^a-z])deep",
    "pork rind", "chicharron", "cheeseburger", "pizza", "donut", "wings",
    "dorados", "sincronizada", "denver", "macaroni", "grilled cheese",
  ].join("|"), "i");
  for (const e of seed) {
    assert.ok(!banned.test(e.name), e.name);
    assert.ok(!banned.test(e.title), e.title);
    if (exercise.test(e.name)) {
      assert.ok(e.avoidWhen.includes("dizzy"), `${e.id} needs avoidWhen dizzy`);
      assert.ok(!e.severities.includes("heavy") &&
        !e.severities.includes("very_heavy"), `${e.id} too hard for heavy`);
    }
    if (/shower/i.test(e.name)) {
      assert.ok(e.avoidWhen.includes("dizzy"), `${e.id} shower fall risk`);
      assert.ok(!e.goodFor.includes("dizzy"), `${e.id} shower not for dizzy`);
    }
    if (e.kind === "activity") {
      assert.ok(!/(^|[^a-z])your?([^a-z]|$)/i.test(e.name), `${e.id} names a person`);
    }
    if (greasy.test(e.name)) {
      assert.ok(e.avoidWhen.includes("nausea"), `${e.id} needs avoidWhen nausea`);
    }
  }
});

test("counts: MX and US each >= 55 breakfasts and >= 28 activities, * >= 85", () => {
  for (const c of ["MX", "US"]) {
    assert.ok(own(c, "breakfast").length >= 55, `${c} breakfasts`);
    assert.ok(own(c, "activity").length >= 28, `${c} activities`);
  }
  assert.ok(own("*").length >= 85);
});

const COMBOS = [
  ...SYMPTOMS.map((s) => [s]),
  ["nausea", "dizzy"],
  ["headache", "wrecked"],
];

test("coverage: every country/symptoms/severity/time/day has >= 3 breakfasts and >= 2 activities", () => {
  const items = seed.map((e) => ({
    ...e, review: "approved", photoStatus: "ready", photoUrl: "x",
  }));
  const none = () => ({30: new Set(), 14: new Set()});
  let minB = Infinity;
  let minA = Infinity;
  for (const country of ["MX", "US", "*"]) {
    for (const symptoms of COMBOS) {
      for (const severity of SEVERITIES) {
        for (const timeOfDay of TIMES) {
          for (const isWorkday of [true, false]) {
            const ctx = {country, symptoms, severity, timeOfDay, isWorkday};
            const r = shortlist(items, ctx, none(), () => 0.5);
            const label = JSON.stringify(ctx);
            assert.ok(r.breakfasts.length >= 3, `breakfasts ${label}`);
            assert.ok(r.activities.length >= 2, `activities ${label}`);
            minB = Math.min(minB, r.breakfasts.length);
            minA = Math.min(minA, r.activities.length);
          }
        }
      }
    }
  }
  console.log(`min breakfasts ${minB}, min activities ${minA}`);
});
