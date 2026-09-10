# Mac steps — fix the empty certificate secret, then ship

## Where things stand

TestFlight delivery is fully wired up and the app builds and tests clean in CI
(87 tests passing). Three build attempts have now failed at the **first** step,
and always for the same reason:

```
decoded 0 bytes
##[error]DIST_CERT_P12_BASE64 is empty.
```

Four of the five required secrets are correct:

| Secret | State |
|---|---|
| `ASC_KEY_ID` | OK |
| `ASC_ISSUER_ID` | OK |
| `ASC_KEY_P8` | OK |
| `DIST_CERT_PASSWORD` | OK |
| `DIST_CERT_P12_BASE64` | **EMPTY — this is the only thing blocking the build** |

Nothing is wrong with the code, the certificate, or the workflow. The secret
simply has no content in it.

## Why it keeps failing silently

```bash
base64 -i ~/Desktop/tracksip.p12 | gh secret set DIST_CERT_P12_BASE64
```

If that path is wrong, `base64` writes its complaint to stderr and puts **nothing**
on stdout. `gh secret set` then cheerfully stores an empty string and reports
success. Both commands "work". The secret ends up empty.

So: **verify the bytes exist before storing them.** Never pipe blind.

---

## Rules for whoever runs this (human or agent)

- **Never `cat`, print, echo or otherwise display the `.p12` or its base64.** It
  contains a private signing key. Pipe it; do not show it.
- **Never ask the user to paste the `.p12` password into a chat.** `DIST_CERT_PASSWORD`
  is already set correctly — do not touch it.
- **Do not paste any secret value into a commit, an issue or a message.**
- Report exact error text on failure. Do not invent workarounds; these steps sign
  and upload a real build to Apple.

---

## 1. Find the file

Do not assume the name or location:

```bash
ls -l ~/Desktop/*.p12 ~/Downloads/*.p12 2>/dev/null
```

If nothing appears, search wider:

```bash
find ~ -name '*.p12' -not -path '*/Library/*' 2>/dev/null | head
```

If there is genuinely no `.p12` anywhere, it was never exported. Do this first:
Xcode → Settings → Accounts → select the team → **Manage Certificates…** →
right-click **Apple Distribution** → **Export Certificate…** → save to Desktop,
and set a password that matches whatever `DIST_CERT_PASSWORD` already holds. If
that password is not known, export with a new one and update the secret too.

## 2. Encode it and CHECK THE SIZE

Substitute the real path from step 1:

```bash
base64 -i ~/Desktop/tracksip.p12 -o /tmp/cert.b64 && wc -c < /tmp/cert.b64
```

**That number must be in the thousands** (a distribution `.p12` is a few KB, so
its base64 is typically 3,000–6,000 characters).

- If it prints `0` or the command errors, the path is wrong. Return to step 1.
- **Do not continue until this number is large.** This is the check that has been
  missing every previous attempt.

## 3. Store it

Only once step 2 printed a large number:

```bash
gh secret set DIST_CERT_P12_BASE64 --repo lorenzoog00/tracksip_ios < /tmp/cert.b64
```

Then clean up the temporary file:

```bash
rm -f /tmp/cert.b64
```

## 4. Confirm all five secrets exist

```bash
gh secret list --repo lorenzoog00/tracksip_ios
```

GitHub secrets are write-only — the value cannot be read back, so this only
confirms the names are present. The real proof is the build in step 5.

## 5. Trigger the build

No new tag needed; the workflow has a manual trigger:

```bash
gh workflow run testflight.yml --ref main --repo lorenzoog00/tracksip_ios
```

## 6. Watch it

```bash
sleep 10 && gh run watch --repo lorenzoog00/tracksip_ios "$(gh run list --workflow=testflight.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
```

The **Install signing certificate** step is the one that has been failing. If it
gets past that, the certificate is good.

- Watch for `decoded NNNN bytes` with a real number — that means the secret took.
- Archive plus upload runs 15–25 minutes.
- App Store Connect then needs 5–15 minutes of processing before the build shows
  up in TestFlight.

First time only: add yourself to **Internal Testing** in App Store Connect.
After that, every build arrives automatically.

## 7. When it succeeds

```bash
rm -f ~/Desktop/tracksip.p12
```

Then delete this file and commit that.

---

## If step 5 fails at a later stage

| Error | Meaning |
|---|---|
| `decoded 0 bytes` | Step 2's check was skipped. The secret is still empty. |
| `Could not read the .p12 ... Mac verify error` | `DIST_CERT_PASSWORD` does not match this `.p12`. Re-set that secret to the password used at export. |
| `No signing certificate "iOS Distribution" found` | An **Apple Development** certificate was exported instead of **Apple Distribution**. |
| `No profiles for 'com.lorenzoog.siptrack' were found` | The App Store Connect API key needs the **App Manager** role, not Developer. |
| `The bundle version must be higher...` | Just re-run; the build number is a UTC timestamp. |

Report the exact error text back rather than guessing.
