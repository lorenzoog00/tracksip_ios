const {test} = require("node:test");
const assert = require("node:assert/strict");
const {
  SYMPTOMS,
  severityOf,
  safetyFlags,
  nightContext,
} = require("./severity");

const dose = (standardDrinks, missingServings = 0) =>
  ({alcoholDose: {standardDrinks, missingServings}});

test("the symptom list is exactly the six the app offers", () => {
  assert.deepEqual(SYMPTOMS,
      ["headache", "nausea", "wrecked", "dizzy", "anxious", "fine"]);
});

test("severity bands follow standard drinks", () => {
  assert.equal(severityOf(dose(2.9)), "light");
  assert.equal(severityOf(dose(3)), "moderate");
  assert.equal(severityOf(dose(5.9)), "moderate");
  assert.equal(severityOf(dose(6)), "heavy");
  assert.equal(severityOf(dose(9.9)), "heavy");
});

test("unknown servings make a night at least heavy", () => {
  assert.equal(severityOf(dose(1.0, 1)), "heavy");
});

test("very heavy starts at 10, or 8 for women", () => {
  assert.equal(severityOf({...dose(10), userSex: "Male"}), "very_heavy");
  assert.equal(severityOf(dose(10)), "very_heavy");
  assert.equal(severityOf({...dose(8), userSex: "Female"}), "very_heavy");
  assert.equal(severityOf({...dose(8), userSex: "Male"}), "heavy");
});

test("dontDrive is true only while estimated BAC is above zero", () => {
  assert.equal(safetyFlags({estimatedBacNow: 0.01}, "light").dontDrive, true);
  assert.equal(safetyFlags({estimatedBacNow: 0}, "light").dontDrive, false);
  assert.equal(safetyFlags({}, "light").dontDrive, false);
  assert.equal(safetyFlags({estimatedBacNow: "0.1"}, "light").dontDrive, false);
});

test("medicalHelp: very heavy, or heavy with nausea and dizziness", () => {
  assert.equal(safetyFlags({symptoms: ["fine"]}, "very_heavy").medicalHelp,
      true);
  assert.equal(
      safetyFlags({symptoms: ["nausea", "dizzy"]}, "heavy").medicalHelp, true);
  assert.equal(safetyFlags({symptoms: ["nausea"]}, "heavy").medicalHelp, false);
  assert.equal(
      safetyFlags({symptoms: ["nausea", "dizzy"]}, "moderate").medicalHelp,
      false);
});

test("nightContext derives time of day, workday and country", () => {
  const base = {symptoms: ["fine"], checkInHour: 10, weekday: 2};
  assert.equal(nightContext(base).timeOfDay, "early");
  assert.equal(nightContext({...base, checkInHour: 11}).timeOfDay, "late");
  assert.equal(nightContext(base).isWorkday, true);
  assert.equal(nightContext({...base, weekday: 1}).isWorkday, false);
  assert.equal(nightContext({...base, weekday: 7}).isWorkday, false);
  assert.equal(nightContext({...base, country: "es"}).country, "ES");
  assert.equal(nightContext(base).country, "*");
  assert.equal(nightContext({...base, country: "USA"}).country, "*");
  assert.deepEqual(nightContext(base).symptoms, ["fine"]);
});
