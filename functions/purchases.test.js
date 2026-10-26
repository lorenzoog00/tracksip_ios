const {test} = require("node:test");
const assert = require("node:assert/strict");
const {verifyPurchase, accountToken} = require("./purchases");

test("missing proof is free and forged proof never grants paid access", async () => {
  assert.equal(await verifyPurchase(null, "alice", {}), null);
  // A proof no configured environment can verify grants nothing, but it is not
  // an error either: it degrades to the free tier, exactly as an expired or
  // refunded purchase does. A sandbox purchase reaches this path while
  // allowSandbox is false, which is what an App Review tester makes, and
  // throwing here showed them a "restore purchases" error right after paying.
  assert.equal(await verifyPurchase("forged.signature", "alice", {
    appAppleId: 123456, allowSandbox: false,
  }), null);
  // Malformed input stays a hard error: that is a broken client, not a receipt.
  await assert.rejects(verifyPurchase("x".repeat(20001), "alice", {}), /Invalid purchase/);
});

test("account token is deterministic and differs between user accounts", () => {
  assert.equal(accountToken("alice"), "2bd806c9-7f0e-00af-1a1f-c3328fa763a9");
  assert.notEqual(accountToken("alice"), accountToken("bob"));
});
