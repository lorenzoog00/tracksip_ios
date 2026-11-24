const {test} = require("node:test");
const assert = require("node:assert/strict");
const {execFileSync} = require("node:child_process");

const HEAVY = "@google-cloud/vision|@anthropic-ai/sdk|@google/genai|" +
  "sharp|app-store-server-library";

// Friend callables cold-start inside the same instance image as the report
// and recovery ones, so everything index.js requires at the top level is paid
// by every cold start. The heavy SDKs must load on first use, not on load.
test("loading index.js does not load the heavy SDKs", () => {
  const script = `
    process.env.GCLOUD_PROJECT = "demo-lazy";
    require(${JSON.stringify(`${__dirname}/index.js`)});
    const re = new RegExp(${JSON.stringify(HEAVY)});
    const hits = Object.keys(require.cache).filter((k) => re.test(k));
    process.stdout.write(JSON.stringify(hits));
  `;
  const out = execFileSync(process.execPath, ["-e", script], {
    encoding: "utf8",
    cwd: __dirname,
  });
  const hits = JSON.parse(out.trim().split("\n").pop());
  assert.deepEqual(hits, [], `heavy modules loaded eagerly: ${hits[0]}`);
});
