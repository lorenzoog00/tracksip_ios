# TestFlight delivery — one-time setup

Push a tag, get a build on your phone. No Mac involved.

```bash
git tag v1.0.1 && git push origin v1.0.1
```

Or run **TestFlight** by hand from the repo's Actions tab.

Everything below is done **once**. Five GitHub secrets, then it's automatic.

> **Never paste these values into a chat, an issue, or a commit.** Pipe them
> straight into `gh secret set`, or paste them into GitHub's secret form in the
> browser. Once stored they are write-only — nobody, including you, can read
> them back out.

---

## 1. App Store Connect API key

App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys** → **+**

- Name it something like `github-actions`
- Role: **App Manager** — needed so the build can create provisioning profiles on its own
- **Download the `.p8` immediately.** Apple lets you download it exactly once.
- Copy the **Key ID** and the **Issuer ID** from that same page

Now add three secrets in the browser — no terminal, no base64:

**github.com/lorenzoog00/tracksip_ios → Settings → Secrets and variables → Actions → New repository secret**

| Name | Value |
|---|---|
| `ASC_KEY_ID` | The Key ID. It's also in the filename: `AuthKey_XXXXXXXXXX.p8` |
| `ASC_ISSUER_ID` | The Issuer ID from the same App Store Connect page |
| `ASC_KEY_P8` | Open the `.p8` in TextEdit and paste **the whole file**, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

The `.p8` is plain text, so it goes in exactly as written.

## 2. Distribution certificate

You already have one, since you've shipped to the App Store. Export it:

**Keychain Access** → **My Certificates** → find **Apple Distribution: … (6T5DB8M42N)** → right-click → **Export** → save as `dist.p12` → set a password when prompted.

```bash
base64 -i dist.p12 | gh secret set DIST_CERT_P12_BASE64
gh secret set DIST_CERT_PASSWORD --body "THE_PASSWORD_YOU_JUST_SET"
```

Delete `dist.p12` afterwards — it's a private key.

## 3. Check

```bash
gh secret list
```

Expect exactly these five:

| Secret | What it is |
|---|---|
| `ASC_KEY_ID` | Key ID from step 1 |
| `ASC_ISSUER_ID` | Issuer ID from step 1 |
| `ASC_KEY_P8` | The `.p8` file's text, pasted whole |
| `DIST_CERT_P12_BASE64` | The `.p12`, base64-encoded |
| `DIST_CERT_PASSWORD` | Password you set on the `.p12` |

---

## How build numbers work

`CFBundleVersion` is now `$(CURRENT_PROJECT_VERSION)` rather than a hardcoded
number, and the workflow passes a UTC timestamp (`202609100430`) on the command
line. That applies to the app, the widget extension and the Watch app together —
App Store Connect rejects an upload whose extensions disagree with the host app,
and it rejects any build number it has already seen. Nothing to bump by hand.

`MARKETING_VERSION` (the `1.0` users see) is still yours to set in Xcode when you
actually release.

## After the first successful upload

- Processing takes roughly 5–15 minutes before the build appears in TestFlight
- Add yourself to **Internal Testing** in App Store Connect once; after that
  every new build reaches your phone automatically
- Apple asks an export-compliance question per build. If the app only uses
  standard HTTPS you can answer it once and for all by adding
  `ITSAppUsesNonExemptEncryption` to `Info.plist` — that's a legal declaration
  about your app, so make that call yourself rather than copying it blindly.

## If it fails

- **"No signing certificate found"** — the `.p12` didn't import. Re-export from
  Keychain Access, making sure you picked the certificate (with the private key
  underneath it), not just the key.
- **"No profiles found"** — the API key needs **App Manager**, not Developer.
- **"The bundle version must be higher"** — an upload already used that number.
  The timestamp scheme prevents this, so it usually means a clock or retry issue;
  just re-run.
