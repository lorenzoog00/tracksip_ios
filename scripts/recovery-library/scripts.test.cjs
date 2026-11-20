const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {execFileSync, spawnSync} = require("node:child_process");

const gen = require("./generate-photos.cjs");
const imp = require("./import-library.cjs");
const sheet = require("./contact-sheet.cjs");

const seed = [
  {id: "a", name: "A", countries: ["US"]},
  {id: "b", name: "B", countries: ["IT"]},
  {id: "c", name: "C<&>", countries: []},
];

test("parseArgs defaults and flags", () => {
  const d = gen.parseArgs([]);
  assert.strictEqual(d.concurrency, 4);
  assert.strictEqual(d.only, null);
  const a = gen.parseArgs(["--only", "a, b", "--concurrency", "2"]);
  assert.deepStrictEqual(a.only, ["a", "b"]);
  assert.strictEqual(a.concurrency, 2);
  assert.throws(() => gen.parseArgs(["--concurrency", "0"]));
  assert.throws(() => gen.parseArgs(["--only"]));
});

test("selectItems skips existing, --only forces regeneration", () => {
  const existing = new Set(["a"]);
  const all = gen.selectItems(seed, existing, null);
  assert.deepStrictEqual(all.toGenerate.map((i) => i.id), ["b", "c"]);
  assert.deepStrictEqual(all.skipped, ["a"]);
  const only = gen.selectItems(seed, existing, ["a", "c"]);
  assert.deepStrictEqual(only.toGenerate.map((i) => i.id), ["a", "c"]);
  assert.throws(() => gen.selectItems(seed, existing, ["zzz"]), /zzz/);
});

test("runPool collects failures without stopping", async () => {
  const r = await gen.runPool(seed, 2, async (i) => {
    if (i.id === "b") throw new Error("boom");
  });
  assert.deepStrictEqual(r.generated.sort(), ["a", "c"]);
  assert.deepStrictEqual(r.failed, [{id: "b", error: "boom"}]);
});

test("import refuses without --confirm-production", () => {
  assert.throws(() => imp.parseArgs(["--bucket", "x"]), /confirm-production/);
  assert.throws(() => imp.parseArgs(["--confirm-production"]), /bucket/);
  const ok = imp.parseArgs(
      ["--confirm-production", "--bucket", "x", "--dry-run"]);
  assert.strictEqual(ok.dryRun, true);
});

test("buildDoc has the required fields", () => {
  const doc = imp.buildDoc(seed[0], {bucket: "bk", token: "tok", now: 5});
  assert.strictEqual(doc.review, "approved");
  assert.strictEqual(doc.photoStatus, "ready");
  assert.deepStrictEqual(doc.pendingPlanPaths, []);
  assert.strictEqual(doc.createdAt, 5);
  assert.strictEqual(doc.name, "A");
  assert.strictEqual(doc.photoUrl,
      "https://firebasestorage.googleapis.com/v0/b/bk/o/" +
      "recovery-library%2Fa.jpg?alt=media&token=tok&v=5");
});

test("splitByPhoto reports missing files", () => {
  const r = imp.splitByPhoto(seed, "/x", (p) => p.endsWith("a.jpg"));
  assert.deepStrictEqual(r.ready.map((i) => i.id), ["a"]);
  assert.deepStrictEqual(r.missing, ["b", "c"]);
});

test("contact sheet outlines flagged ids and escapes html", () => {
  const html = sheet.buildHtml(seed, new Map([["b", "melted"]]),
      new Set(["a", "b"]));
  assert.match(html, /class="flagged"><img src="b\.jpg"/);
  assert.match(html, /melted/);
  assert.match(html, /C&lt;&amp;&gt;/);
  assert.match(html, /no photo/);
});

test("fake generation, skip logic and dry-run import end to end", () => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "recovery-"));
  const env = {...process.env, RECOVERY_FAKE_IMAGES: "1"};
  const run = (script, ...args) => execFileSync(process.execPath,
      [path.join(__dirname, script), "--out", out, ...args],
      {env, encoding: "utf8"});
  const ids = require("../../functions/recovery/library-seed.json")
      .slice(0, 2).map((i) => i.id);
  run("generate-photos.cjs", "--only", ids.join(","));
  assert.ok(ids.every((id) => fs.existsSync(path.join(out, `${id}.jpg`))));
  const again = run("generate-photos.cjs", "--only", ids[0]);
  assert.match(again, /to generate 1,/);
  const dry = run("import-library.cjs", "--confirm-production",
      "--bucket", "test-bucket", "--dry-run");
  assert.match(dry, /DRY RUN/);
  assert.match(dry, new RegExp(`would set recovery_library/${ids[0]}`));
  assert.match(dry, /would import 2 of /);
  const refused = spawnSync(process.execPath,
      [path.join(__dirname, "import-library.cjs"), "--bucket", "x"],
      {encoding: "utf8"});
  assert.notStrictEqual(refused.status, 0);
  fs.rmSync(out, {recursive: true, force: true});
});

test("every script throws on an unknown flag before doing any work", () => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "recovery-flag-"));
  const env = {...process.env, RECOVERY_FAKE_IMAGES: "1"};
  assert.throws(() => gen.parseArgs(["--onyl", "a"]), /Unknown flag: --onyl/);
  assert.throws(() => gen.parseArgs(["--concurency", "2"]), /Unknown flag/);
  assert.throws(() => imp.parseArgs(
      ["--confirm-production", "--bucket", "x", "--dryrun"]), /Unknown flag/);
  for (const script of ["generate-photos.cjs", "contact-sheet.cjs"]) {
    const r = spawnSync(process.execPath,
        [path.join(__dirname, script), "--out", out, "--onyl", "a"],
        {env, encoding: "utf8"});
    assert.notStrictEqual(r.status, 0, script);
    assert.deepStrictEqual(fs.readdirSync(out), [], `${script} did work`);
  }
  const r = spawnSync(process.execPath,
      [path.join(__dirname, "import-library.cjs"), "--confirm-production",
        "--bucket", "x", "--out", out, "--dryrun"], {encoding: "utf8"});
  assert.notStrictEqual(r.status, 0);
  assert.match(r.stderr, /Unknown flag/);
  fs.rmSync(out, {recursive: true, force: true});
});

test("import --only limits the run and rejects unknown ids", () => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "recovery-only-"));
  const env = {...process.env, RECOVERY_FAKE_IMAGES: "1"};
  const ids = require("../../functions/recovery/library-seed.json")
      .slice(0, 2).map((i) => i.id);
  const gen1 = spawnSync(process.execPath,
      [path.join(__dirname, "generate-photos.cjs"), "--out", out,
        "--only", ids.join(",")], {env, encoding: "utf8"});
  assert.strictEqual(gen1.status, 0);
  const base = [path.join(__dirname, "import-library.cjs"),
    "--confirm-production", "--bucket", "b", "--dry-run", "--out", out];
  assert.deepStrictEqual(imp.parseArgs(
      ["--confirm-production", "--bucket", "b", "--only", "a,b"]).only,
  ["a", "b"]);
  const one = spawnSync(process.execPath, [...base, "--only", ids[1]],
      {encoding: "utf8"});
  assert.match(one.stdout, /would import 1 of 1/);
  assert.doesNotMatch(one.stdout, new RegExp(`recovery_library/${ids[0]}\b`));
  const bad = spawnSync(process.execPath, [...base, "--only", "nope"],
      {encoding: "utf8"});
  assert.notStrictEqual(bad.status, 0);
  assert.match(bad.stderr, /Unknown ids/);
  fs.rmSync(out, {recursive: true, force: true});
});
