const {test} = require("node:test");
const assert = require("node:assert/strict");
const {buildPrompt, formatAlcoholLog} = require("./prompts");
const {validateRequest} = require("./report-policy");

const vodka = {
  name: "Vodka", quantity: 1, volumeMlPerServing: 2000, abv: 40,
  grams: 631.2, standardDrinks: 631.2 / 14,
};
const highDose = {
  nightOutcome: "solid", peakBac: 0.01, waterMl: 1000, totalCalories: 4409,
  drinks: [vodka],
  alcoholDose: {
    grams: vodka.grams, standardDrinks: vodka.standardDrinks,
    loggedServings: 1, missingServings: 0, otherGroups: 0, otherGrams: 0,
    largestEntry: vodka, strongestHourStandardDrinks: vodka.standardDrinks,
    strongestHourStartMinute: 0,
  },
};

test("a single 2 L vodka log leads with 45.1 standard drinks and risk", () => {
  assert.doesNotThrow(() => validateRequest({
    kind: "night", id: "large", payload: highDose,
  }));
  const text = formatAlcoholLog(highDose);
  assert.match(text, /^ALCOHOL LOGGED:/);
  assert.match(text, /631\.2 g.*45\.1 U\.S\. standard drinks/);
  assert.match(text, /2,000 mL of Vodka at 40% ABV/);
  assert.match(text, /high amount for one night.*Check the volume and ABV/);
  assert.match(text, /emergency services immediately/);
  const prompt = buildPrompt("night", highDose);
  assert.match(prompt.prompt, /TONIGHT, TOMORROW, NEXT TIME/);
  assert.match(prompt.prompt, /alcohol poisoning risk directly/);
  assert.doesNotMatch(prompt.prompt, /GREAT CALL|"nightOutcome":"solid"/);
  assert.match(prompt.system, /Water and calories are separate observations/);
});

test("a missing dose is reported as unknown and a legacy count is not a dose", () => {
  const data = {
    drinks: [],
    alcoholDose: {
      grams: 0, standardDrinks: 0, loggedServings: 1, missingServings: 1,
      otherGroups: 0, otherGrams: 0,
    },
    nightOutcome: "sober",
  };
  assert.match(formatAlcoholLog(data), /unavailable for 1 logged serving/);
  assert.doesNotMatch(formatAlcoholLog(data), /0 U\.S\. standard drinks/);
  assert.doesNotMatch(buildPrompt("night", data).prompt, /BODY RESET/);
  const legacy = {nightOutcome: "solid", drinks: [{name: "Vodka", quantity: 1}]};
  assert.equal(formatAlcoholLog(legacy), "");
  assert.match(buildPrompt("night", legacy).system, /Never infer a dose from legacy counts alone/);
});

test("dose validation rejects totals that undercount the actual logged pour", () => {
  const invalid = {
    ...highDose,
    alcoholDose: {...highDose.alcoholDose, grams: 14, standardDrinks: 1},
  };
  assert.throws(() => validateRequest({
    kind: "night", id: "large", payload: invalid,
  }), /Invalid alcohol dose/);
});

test("period reports do not treat a weekly total as one occasion", () => {
  assert.doesNotMatch(buildPrompt("weekly", highDose).prompt, /Lead with the high logged dose/);
  assert.match(buildPrompt("recovery", highDose).prompt, /Lead with the high logged dose/);
});
