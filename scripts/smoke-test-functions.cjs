#!/usr/bin/env node
//
// After a deploy, prove every callable in functions/index.js is live.
//
// A callable that is in the source but was never deployed answers with an HTML
// 404 page, which the app turns into "Something went wrong" — that is how
// deleteAccount shipped broken once. A deployed callable answers a bare
// unauthenticated POST with a JSON error envelope (401 / 400 / 403), so JSON
// means "deployed", whatever the status.
//
// Usage: node scripts/smoke-test-functions.cjs <project-id> [region]

/// Names of the callable functions exported by a functions module.
function callableNames(moduleExports) {
  return Object.entries(moduleExports)
      .filter(([, value]) => value && value.__endpoint &&
        value.__endpoint.callableTrigger !== undefined)
      .map(([name]) => name)
      .sort();
}

/// Whether a response came from a deployed callable rather than a 404 page.
function isDeployedResponse(status, body) {
  if (status === 404) return false;
  try {
    const parsed = JSON.parse(body);
    return parsed !== null && typeof parsed === "object";
  } catch {
    return false;
  }
}

async function main() {
  const [project, region = "us-central1"] = process.argv.slice(2);
  if (!project) {
    console.error("usage: smoke-test-functions.cjs <project-id> [region]");
    process.exit(2);
  }
  const names = callableNames(require("../functions/index.js"));
  const missing = [];
  for (const name of names) {
    const url = `https://${region}-${project}.cloudfunctions.net/${name}`;
    let status = 0;
    let body = "";
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({data: {}}),
      });
      status = response.status;
      body = await response.text();
    } catch (error) {
      body = String(error);
    }
    const ok = isDeployedResponse(status, body);
    console.log(`${ok ? "ok     " : "MISSING"} ${name} (${status})`);
    if (!ok) missing.push(name);
  }
  if (missing.length > 0) {
    console.log(`::error::not deployed: ${missing.join(", ")}`);
    process.exit(1);
  }
  console.log(`${names.length} callables live`);
}

if (require.main === module) {
  main().then(() => process.exit(0));
}

module.exports = {callableNames, isDeployedResponse};
