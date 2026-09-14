const {test} = require("node:test");
const assert = require("node:assert/strict");
const {verifyPurchase, accountToken} = require("./purchases");

test("missing proof is free and forged proof never grants paid access", async () => {
  assert.equal(await verifyPurchase(null, "alice", {}), null);
  await assert.rejects(verifyPurchase("forged.signature", "alice", {
    appAppleId: 123456, allowSandbox: false,
  }), /could not be verified/);
  await assert.rejects(verifyPurchase("x".repeat(20001), "alice", {}), /Invalid purchase/);
});

test("account token is deterministic and differs between user accounts", () => {
  assert.equal(accountToken("alice"), "2bd806c9-7f0e-00af-1a1f-c3328fa763a9");
  assert.notEqual(accountToken("alice"), accountToken("bob"));
});
