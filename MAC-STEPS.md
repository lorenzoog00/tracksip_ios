# Mac steps — finish TestFlight setup and ship the first build

Everything on the Windows side is done. These three secrets are already in GitHub:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.

Two secrets left, then a tag ships a build to TestFlight.

The certificate is at `~/Desktop/tracksip.p12`.

---

## Rules for whoever runs this (human or agent)

- **Never read, `cat`, print, or echo the contents of `tracksip.p12`.** It holds a
  private signing key. Only pipe it into `base64 | gh secret set`.
- **Never ask the user to type or paste the `.p12` password into a chat.** Step 3
  reads it from a hidden prompt so it never reaches shell history or a transcript.
- **Never paste any secret value into a commit, an issue, or a message.**
- If a command fails, report the **exact error text** and stop. Do not improvise a
  workaround — the remaining steps sign and upload a real build to Apple.

---

## 1. Check it is the right certificate

Run from anywhere. It will prompt for the password you set when exporting.

```bash
openssl pkcs12 -in ~/Desktop/tracksip.p12 -nokeys | openssl x509 -noout -subject -enddate
```

The subject must contain **`Apple Distribution`** and **`6T5DB8M42N`**.

- If it says `Apple Development`, the wrong certificate was exported. Redo the
  export: Xcode → Settings → Accounts → team → Manage Certificates → right-click
  **Apple Distribution** → Export Certificate.
- If openssl complains about an unsupported algorithm, add `-legacy` before the
  first pipe. (macOS ships LibreSSL, which usually does not need it; OpenSSL 3
  usually does.)
- If `enddate` is in the past, the certificate is expired — create a new one in
  that same Manage Certificates panel.

## 2. Store the certificate

```bash
base64 -i ~/Desktop/tracksip.p12 | gh secret set DIST_CERT_P12_BASE64 --repo lorenzoog00/tracksip_ios
```

## 3. Store its password

This prompts and hides what is typed. **The user types it — nobody else.**

```bash
gh secret set DIST_CERT_PASSWORD --repo lorenzoog00/tracksip_ios
```

If the export was made with **no** password, use this instead:

```bash
printf '' | gh secret set DIST_CERT_PASSWORD --repo lorenzoog00/tracksip_ios
```

## 4. Confirm all five are present

```bash
gh secret list --repo lorenzoog00/tracksip_ios
```

Expected, exactly: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`,
`DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`.

## 5. Ship

```bash
git pull && git tag v1.0.1 && git push origin v1.0.1
```

## 6. Watch it

```bash
gh run watch --repo lorenzoog00/tracksip_ios "$(gh run list --workflow=testflight.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Archive and upload take roughly 15–25 minutes. After the upload succeeds, App
Store Connect needs another 5–15 minutes to process before the build shows up in
TestFlight.

First time only: add yourself to **Internal Testing** in App Store Connect. After
that every build arrives automatically.

## 7. Clean up

```bash
rm ~/Desktop/tracksip.p12
```

Then delete this file and commit that.

---

## Known failure modes

| Error | Cause |
|---|---|
| `No signing certificate "iOS Distribution" found` | Wrong certificate exported, or `DIST_CERT_PASSWORD` does not match the `.p12` |
| `No profiles for 'com.lorenzoog.siptrack' were found` | The App Store Connect API key needs the **App Manager** role, not Developer |
| `The bundle version must be higher than the previously uploaded version` | Re-run; the build number is a UTC timestamp and should not collide |
| `Invalid Provisioning Profile` on the Watch app | The Watch target needs its own profile; automatic signing should create it, but the API key must have App Manager |

## What is already verified

CI is green on this commit — 87 tests pass, and the app builds clean for the iOS
Simulator. So a failure here is about signing or upload, not about the code.
