import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import {certificatesToRevoke, buildToken, describeCertificates} from "./revoke-ci-certificates.mjs";

const certificate = (name, certificateType) => ({
  id: `${name}-${certificateType}`,
  attributes: {name, certificateType, expirationDate: "2027-11-02"},
});

// Revoking cannot be undone, so the filter is the part worth pinning: on
// 2026-11-02 eleven API-created development certificates had to be cleared by
// hand, alongside five real ones that had to survive untouched.

test("takes the throwaways the API created", () => {
  const stale = certificatesToRevoke([
    certificate("Created via API", "DEVELOPMENT"),
    certificate("Created via API", "IOS_DEVELOPMENT"),
  ]);
  assert.equal(stale.length, 2);
});

test("leaves every distribution certificate alone", () => {
  const stale = certificatesToRevoke([
    certificate("Created via API", "DISTRIBUTION"),
    certificate("Created via API", "IOS_DISTRIBUTION"),
    certificate("Created via API", "DISTRIBUTION_MANAGED"),
  ]);
  assert.deepEqual(stale, []);
});

test("leaves a person's own certificates alone, development included", () => {
  // The one the developer signs with on their own Mac.
  const stale = certificatesToRevoke([
    certificate("Lorenzo Orozco", "DEVELOPMENT"),
    certificate("Lorenzo Orozco", "IOS_DISTRIBUTION"),
  ]);
  assert.deepEqual(stale, []);
});

test("picks only the throwaways out of a mixed account", () => {
  const stale = certificatesToRevoke([
    certificate("Created via API", "DEVELOPMENT"),
    certificate("Lorenzo Orozco", "DEVELOPMENT"),
    certificate("Created via API", "DISTRIBUTION"),
    certificate("Created via API", "DEVELOPMENT"),
  ]);
  assert.equal(stale.length, 2);
  assert.ok(stale.every((c) => c.attributes.name === "Created via API"));
  assert.ok(stale.every((c) => c.attributes.certificateType === "DEVELOPMENT"));
});

test("ignores a certificate with no attributes rather than throwing", () => {
  assert.deepEqual(certificatesToRevoke([{id: "x"}, {id: "y", attributes: {}}]), []);
});

// 2026-11-17: the exact-name match found 0 of 14 while the cap was hit, so the
// marker can sit inside a longer name or only in displayName.
test("finds the marker inside a longer name or only in displayName", () => {
  const stale = certificatesToRevoke([
    certificate("Apple Development: Created via API (ABC123)", "DEVELOPMENT"),
    {id: "d", attributes: {name: "Lorenzo Orozco", displayName: "Created via API",
      certificateType: "DEVELOPMENT"}},
    certificate("created VIA api", "IOS_DEVELOPMENT"),
  ]);
  assert.equal(stale.length, 3);
});

test("still leaves CI-made distribution and the long-lived CI development cert alone", () => {
  const stale = certificatesToRevoke([
    certificate("Apple Distribution: Created via API (ABC123)", "DISTRIBUTION"),
    certificate("TrackSip CI Development", "DEVELOPMENT"),
  ]);
  assert.deepEqual(stale, []);
});

test("describes every certificate so an empty run explains itself", () => {
  const lines = describeCertificates([
    certificate("Lorenzo Orozco", "DEVELOPMENT"),
    {id: "z"},
  ]);
  assert.equal(lines.length, 2);
  assert.match(lines[0], /DEVELOPMENT \| name="Lorenzo Orozco"/);
});

test("signs a token Apple will accept", () => {
  const {privateKey} = crypto.generateKeyPairSync("ec", {namedCurve: "P-256"});
  const token = buildToken({
    keyId: "KEY123",
    issuerId: "ISSUER456",
    privateKey,
    now: 1_762_000_000_000,
    sign: (input, key) =>
      crypto
          .sign("sha256", Buffer.from(input), {key, dsaEncoding: "ieee-p1363"})
          .toString("base64url"),
  });

  const [header, payload, signature] = token.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url").toString()), {
    alg: "ES256", kid: "KEY123", typ: "JWT",
  });
  const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
  assert.equal(claims.iss, "ISSUER456");
  assert.equal(claims.aud, "appstoreconnect-v1");
  assert.equal(claims.exp - claims.iat, 600, "Apple rejects a window over 20 minutes");
  // ES256 is a raw 64-byte r||s pair. DER encoding is the usual mistake and
  // Apple answers it with a flat 401.
  assert.equal(Buffer.from(signature, "base64url").length, 64);
});
