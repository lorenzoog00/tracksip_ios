const {test} = require("node:test");
const assert = require("node:assert/strict");
const {normalizeName, shortlist, findDuplicate} = require("./library");

let seq = 0;
const item = (over = {}) => {
  seq += 1;
  return {
    id: `i${seq}`,
    name: `Item ${seq}`,
    kind: "breakfast",
    countries: ["*"],
    goodFor: [],
    avoidWhen: [],
    severities: ["light", "moderate", "heavy", "very_heavy"],
    effort: "buy",
    timeOfDay: ["early", "late"],
    normalizedName: `item ${seq}`,
    photoUrl: "https://example.com/p.jpg",
    photoStatus: "ready",
    review: "approved",
    createdAt: seq,
    pendingPlanPaths: [],
    ...over,
  };
};
const ctx = (over = {}) => ({
  country: "MX",
  symptoms: ["headache"],
  severity: "moderate",
  timeOfDay: "early",
  isWorkday: false,
  ...over,
});
const none = {30: new Set(), 14: new Set()};
const fixed = () => 0.5;
const ids = (list) => list.map((i) => i.id);

test("only approved items with a ready photo are returned", () => {
  const ok = item();
  const items = [
    ok,
    item({review: "pending"}),
    item({review: "rejected"}),
    item({photoStatus: "generating"}),
    item({photoStatus: "failed"}),
    item({photoStatus: "capped"}),
  ];
  assert.deepEqual(ids(shortlist(items, ctx(), none, fixed).breakfasts),
      [ok.id]);
});

test("returned items keep their id and fields", () => {
  const a = item({effort: "cook"});
  const [out] = shortlist([a], ctx(), none, fixed).breakfasts;
  assert.equal(out.id, a.id);
  assert.equal(out.effort, "cook");
});

test("MX gets MX and shared items but never US", () => {
  const mx = item({countries: ["MX"]});
  const us = item({countries: ["US"]});
  const all = item({countries: ["*"]});
  const out = shortlist([mx, us, all], ctx(), none, fixed).breakfasts;
  assert.deepEqual(ids(out).sort(), [mx.id, all.id].sort());
});

test("ES gets only shared items and all 5 shared breakfasts", () => {
  const shared = [1, 2, 3, 4, 5].map(() => item());
  const items = [...shared, item({countries: ["MX"]}),
    item({countries: ["US"]})];
  const out = shortlist(items, ctx({country: "ES"}), none, fixed).breakfasts;
  assert.deepEqual(ids(out).sort(), ids(shared).sort());
});

test("avoidWhen excludes items matching a symptom", () => {
  const bad = item({avoidWhen: ["nausea"]});
  const good = item();
  const out = shortlist([bad, good],
      ctx({symptoms: ["nausea", "headache"]}), none, fixed).breakfasts;
  assert.deepEqual(ids(out), [good.id]);
  const out2 = shortlist([bad, good], ctx({symptoms: ["headache"]}),
      none, fixed).breakfasts;
  assert.equal(out2.length, 2);
});

test("severity and timeOfDay filters apply", () => {
  const heavyOnly = item({severities: ["heavy"]});
  const lateOnly = item({timeOfDay: ["late"]});
  const fits = item();
  const out = shortlist([heavyOnly, lateOnly, fits], ctx(), none, fixed)
      .breakfasts;
  assert.deepEqual(ids(out), [fits.id]);
});

test("30-day history is excluded when 3 or more remain", () => {
  const items = [1, 2, 3, 4].map(() => item());
  const history = {30: new Set([items[0].id]), 14: new Set()};
  const out = shortlist(items, ctx(), history, fixed).breakfasts;
  assert.deepEqual(ids(out).sort(), ids(items.slice(1)).sort());
});

test("falls back to the 14-day set when 30-day leaves under 3", () => {
  const items = [1, 2, 3, 4].map(() => item());
  const history = {
    30: new Set([items[0].id, items[1].id]),
    14: new Set([items[0].id]),
  };
  const out = shortlist(items, ctx(), history, fixed).breakfasts;
  assert.deepEqual(ids(out).sort(), ids(items.slice(1)).sort());
});

test("ignores history when even the 14-day set leaves under 3", () => {
  const items = [1, 2, 3].map(() => item());
  const history = {
    30: new Set(ids(items)),
    14: new Set([items[0].id]),
  };
  const out = shortlist(items, ctx(), history, fixed).breakfasts;
  assert.deepEqual(ids(out).sort(), ids(items).sort());
});

test("history fallback is decided per kind", () => {
  const bs = [1, 2, 3, 4].map(() => item());
  const as = [1, 2].map(() => item({kind: "activity"}));
  const history = {30: new Set([bs[0].id, as[0].id]), 14: new Set()};
  const out = shortlist([...bs, ...as], ctx(), history, fixed);
  assert.deepEqual(ids(out.breakfasts).sort(), ids(bs.slice(1)).sort());
  assert.deepEqual(ids(out.activities).sort(), ids(as).sort());
});

test("caps are 12 breakfasts and 10 activities", () => {
  const items = [];
  for (let i = 0; i < 40; i++) items.push(item());
  for (let i = 0; i < 30; i++) items.push(item({kind: "activity"}));
  const out = shortlist(items, ctx(), none, Math.random);
  assert.equal(out.breakfasts.length, 12);
  assert.equal(out.activities.length, 10);
});

test("items that fit the symptoms rank before ones that do not", () => {
  const plain = item();
  const match = item({goodFor: ["headache"]});
  const two = item({goodFor: ["headache", "nausea"]});
  const out = shortlist([plain, match, two],
      ctx({symptoms: ["headache", "nausea"]}), none, fixed).breakfasts;
  assert.deepEqual(ids(out), [two.id, match.id, plain.id]);
});

test("on workdays buy and none breakfasts rank before cook", () => {
  const cook = item({effort: "cook"});
  const buy = item({effort: "buy"});
  const nothing = item({effort: "none"});
  const items = [cook, buy, nothing];
  const work = shortlist(items, ctx({isWorkday: true}), none, fixed)
      .breakfasts;
  assert.equal(work[2].id, cook.id);
  const off = shortlist(items, ctx({isWorkday: false}), none, () => 0)
      .breakfasts;
  assert.equal(off.length, 3);
});

test("symptom fit still outranks the workday effort preference", () => {
  const cookMatch = item({effort: "cook", goodFor: ["headache"]});
  const buy = item({effort: "buy"});
  const out = shortlist([buy, cookMatch], ctx({isWorkday: true}), none,
      fixed).breakfasts;
  assert.equal(out[0].id, cookMatch.id);
});

test("equal items are ordered by the injected rng", () => {
  const items = [1, 2, 3, 4].map(() => item());
  const a = shortlist(items, ctx(), none, () => 0).breakfasts;
  const b = shortlist(items, ctx(), none, () => 0).breakfasts;
  assert.deepEqual(ids(a), ids(b));
  let n = 0;
  const seq2 = [0.9, 0.1, 0.5, 0.3, 0.7, 0.2];
  const c = shortlist(items, ctx(), none, () => seq2[n++ % seq2.length])
      .breakfasts;
  const n2 = ids(c).slice().sort();
  assert.deepEqual(n2, ids(items).slice().sort());
});

test("shortlist does not mutate its input", () => {
  const items = [item(), item(), item()];
  const copy = items.slice();
  shortlist(items, ctx(), none, Math.random);
  assert.deepEqual(items, copy);
});

test("normalizeName ignores case, accents, punctuation and spacing", () => {
  assert.equal(normalizeName("Huevos Rancheros!"),
      normalizeName("huevos  rancheros"));
  assert.equal(normalizeName("Café con Leche"), "cafe con leche");
  assert.equal(normalizeName("The Big Breakfast"), "big breakfast");
  assert.equal(normalizeName("An apple"), "apple");
  assert.equal(normalizeName("A walk"), "walk");
  assert.equal(normalizeName("Another thing"), "another thing");
});

test("findDuplicate matches by normalized name within country or *", () => {
  const mx = item({countries: ["MX"], normalizedName: "chilaquiles"});
  const us = item({countries: ["US"], normalizedName: "bagel"});
  const shared = item({countries: ["*"], normalizedName: "toast"});
  const items = [mx, us, shared];
  assert.equal(findDuplicate(items, "Chilaquiles!", "MX").id, mx.id);
  assert.equal(findDuplicate(items, "Chilaquiles", "US"), null);
  assert.equal(findDuplicate(items, "Bagel", "MX"), null);
  assert.equal(findDuplicate(items, "the toast", "MX").id, shared.id);
});

test("findDuplicate ignores rejected items", () => {
  const rejected = item({normalizedName: "toast", review: "rejected"});
  assert.equal(findDuplicate([rejected], "Toast", "MX"), null);
  const pending = item({normalizedName: "toast", review: "pending"});
  assert.equal(findDuplicate([rejected, pending], "Toast", "MX").id,
      pending.id);
});
