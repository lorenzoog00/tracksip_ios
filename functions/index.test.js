const {test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");

// The handlers build their Firestore and Auth clients at call time, and the
// unit and emulator tests inject an already-built `db`, so nothing here ever
// exercised index.js's own wiring. firebase-admin 14 removed the namespaced
// API, and `admin.firestore()` kept parsing, linting and deploying cleanly —
// then threw "admin.firestore is not a function" on the first real request,
// which reached the app as a bare "Internal" with a green CI behind it.
test("index.js does not use the admin API removed in firebase-admin 14", () => {
  // Comments are stripped first: prose that merely names the old calls, such
  // as the note in index.js explaining this very rule, is not a usage.
  const code = readFileSync(`${__dirname}/index.js`, "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/\/\/.*$/gm, "");
  const removed = /\badmin\s*\.\s*(firestore|auth|storage|database)\s*\(/;
  assert.equal(
      removed.test(code),
      false,
      "use getFirestore()/getAuth() from firebase-admin/<service> instead",
  );
});

test("index.js imports the modular admin entry points it needs", () => {
  const source = readFileSync(`${__dirname}/index.js`, "utf8");
  for (const entry of [
    "firebase-admin/app",
    "firebase-admin/firestore",
    "firebase-admin/auth",
  ]) {
    assert.ok(source.includes(entry), `missing require of ${entry}`);
  }
});

test("the major version of firebase-admin still matches this import style", () => {
  const pkg = JSON.parse(readFileSync(`${__dirname}/package.json`, "utf8"));
  const range = pkg.dependencies["firebase-admin"];
  const major = Number(String(range).replace(/^[^0-9]*/, "").split(".")[0]);
  // A downgrade below 14 would not break these imports, but an upgrade past
  // the next major could move them again — fail loudly rather than at runtime.
  assert.ok(major >= 14, `firebase-admin ${range} predates the modular-only API`);
  assert.ok(major <= 14, `firebase-admin ${range} is newer than this was checked against`);
});
