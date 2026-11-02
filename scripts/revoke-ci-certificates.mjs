#!/usr/bin/env node
//
// Frees a slot in Apple's certificate limit before the archive runs.
//
// `xcodebuild -allowProvisioningUpdates` mints a fresh **development**
// certificate on most runs, for the watch and widget targets. Apple caps how
// many an account may hold, so after roughly seven releases the archive fails
// with "Your account has reached the maximum number of certificates" — and,
// confusingly, with "no iOS App Development provisioning profiles found",
// because signing falls back once Apple refuses to issue anything.
//
// The distribution certificate is a real, persistent one installed from
// secrets; it is never touched here. The ones this removes are the throwaways
// the API itself created, which Apple names "Created via API" and which are
// used by exactly one build each.
//
// Housekeeping must never be the reason a release does not ship, so every
// failure here is reported and swallowed.

const API = "https://api.appstoreconnect.apple.com/v1";

/// Which certificates are safe to remove.
///
/// Deliberately narrow, because revoking cannot be undone. A certificate has
/// to be *both* API-created and a development one. Anything a person made
/// carries their name instead, and every distribution certificate is left
/// alone whatever it is called.
export function certificatesToRevoke(certificates) {
  return certificates.filter((certificate) => {
    const {name, certificateType} = certificate.attributes ?? {};
    if (name !== "Created via API") return false;
    if (typeof certificateType !== "string") return false;
    if (!certificateType.includes("DEVELOPMENT")) return false;
    return true;
  });
}

export function buildToken({keyId, issuerId, privateKey, now = Date.now(), sign}) {
  const issuedAt = Math.floor(now / 1000);
  const header = {alg: "ES256", kid: keyId, typ: "JWT"};
  const payload = {
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + 600,
    aud: "appstoreconnect-v1",
  };
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const signingInput = `${encode(header)}.${encode(payload)}`;
  return `${signingInput}.${sign(signingInput, privateKey)}`;
}

async function main() {
  const {default: crypto} = await import("node:crypto");
  const {readFileSync} = await import("node:fs");

  const keyId = process.env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID;
  const keyPath = process.env.ASC_KEY_PATH;
  if (!keyId || !issuerId || !keyPath) {
    console.log("::warning::certificate cleanup skipped: ASC credentials not set");
    return;
  }

  const token = buildToken({
    keyId,
    issuerId,
    privateKey: readFileSync(keyPath, "utf8"),
    // ES256 wants the raw r||s pair; the default DER encoding is rejected.
    sign: (input, key) =>
      crypto
          .sign("sha256", Buffer.from(input), {key, dsaEncoding: "ieee-p1363"})
          .toString("base64url"),
  });

  const headers = {Authorization: `Bearer ${token}`};
  const response = await fetch(`${API}/certificates?limit=200`, {headers});
  if (!response.ok) {
    console.log(`::warning::certificate cleanup skipped: list returned ${response.status}`);
    return;
  }

  const {data = []} = await response.json();
  const stale = certificatesToRevoke(data);
  console.log(`${data.length} certificate(s) on the account, ${stale.length} created by CI`);
  if (stale.length === 0) return;

  for (const certificate of stale) {
    const {id} = certificate;
    const {certificateType, expirationDate} = certificate.attributes ?? {};
    const result = await fetch(`${API}/certificates/${id}`, {method: "DELETE", headers});
    if (result.ok) {
      console.log(`revoked ${certificateType} ${id} (expired ${expirationDate})`);
    } else {
      console.log(`::warning::could not revoke ${id}: ${result.status}`);
    }
  }
}

// Only run when invoked directly, so the tests can import the pure parts.
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].replace(/\\/g, "/"))) {
  main().catch((error) => {
    console.log(`::warning::certificate cleanup failed: ${error.message}`);
  });
}
