const test = require("node:test");
const assert = require("node:assert/strict");
const {callableNames, isDeployedResponse} = require("./smoke-test-functions.cjs");

test("picks only callables out of the exports", () => {
  const names = callableNames({
    b: {__endpoint: {callableTrigger: {}}},
    a: {__endpoint: {callableTrigger: {}}},
    scheduled: {__endpoint: {scheduleTrigger: {}}},
    helper: () => {},
    nothing: null,
  });
  assert.deepEqual(names, ["a", "b"]);
});

test("a JSON error envelope means deployed, whatever the status", () => {
  assert.equal(isDeployedResponse(401, '{"error":{"status":"UNAUTHENTICATED"}}'), true);
  assert.equal(isDeployedResponse(400, '{"error":{}}'), true);
});

test("an HTML 404 page or a network failure means not deployed", () => {
  assert.equal(isDeployedResponse(404, "<html>Page not found</html>"), false);
  assert.equal(isDeployedResponse(404, '{"error":"x"}'), false);
  assert.equal(isDeployedResponse(0, "TypeError: fetch failed"), false);
  assert.equal(isDeployedResponse(500, "null"), false);
});
