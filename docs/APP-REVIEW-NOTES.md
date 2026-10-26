# App Review notes — TrackSip

Maintained for the "App Review Information → Notes" field in App Store Connect.
Part 1 is the text to paste. Part 2 is internal: the longer argument if a reviewer
pushes back, plus the checks to run before each submission.

---

## Part 1 — Paste into App Store Connect

> The demo account's email and password belong in App Store Connect's own
> **Sign-In Information** fields (App Review Information → "Sign-in required"),
> and never in this file. **This repository is public**: a password committed
> here would be published and would stay in the git history even after being
> removed. Nothing in the block below is secret, so it can be pasted as is.

```text
DEMO ACCOUNT

Please sign in with the demo account given in the Sign-In Information fields
rather than creating a new one. That account is already email-verified and has
several completed nights in its history, so Stats, Calendar and the AI Coach
all have data to show.

TrackSip uses email verification: a newly created email/password account cannot
sign in until the link we email has been opened. If you create a fresh account
with a throwaway address and do not open that link, sign-in will correctly
refuse and return you to the sign-in screen. "Sign in with Apple" is also
available and needs no verification step.

A previous build (1.0.1) had a bug where signing up appeared to reload the
sign-in screen. That is fixed in this build.

WHY TRACKSIP REQUIRES AN ACCOUNT (Guideline 5.1.1(v))

TrackSip's account-based features are core to the app, not incidental:

1. Cross-device history. A user's nights, drink entries, custom drinks,
   challenges and reports are stored per-account in Firestore and restored when
   they sign in on another device or after reinstalling. Drinking history is the
   product; losing it with the device would make the app useless.

2. Server-generated AI reports. Night reports, next-morning recovery briefs,
   weekly/monthly reviews and night-to-night comparisons are produced by our
   authenticated backend (a Firebase Cloud Function calling Anthropic's Claude
   API), not on the device. The function rejects unauthenticated calls, and the
   monthly free-report allowance is metered per account on the server. There is
   no way to offer this feature without an identified account.

3. Subscription entitlement. TrackSip Pro is bound to the account: the signed
   App Store transaction is verified server-side against the signed-in user, so
   a subscription follows the person across their devices and cannot be shared
   between accounts.

We ask for as little as possible. Registration takes an email address and
password, or Sign in with Apple, or Google — no phone number, no contacts, no
social accounts. Sign in with Apple is offered first and works with Apple's
private relay addresses. Body details used for the BAC estimate (sex, weight,
and optionally height and birth year) are entered after sign-in, are used only
for that calculation, and are not required to create the account.

Users can delete their account and all associated cloud data from inside the
app: Profile → Account → Delete Account.

Privacy Policy: https://looqs.online/siptrack/policy
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

TrackSip estimates blood alcohol content for informational purposes only. The
app is not a medical device, its estimates are not a substitute for a
breathalyser, and it does not tell anyone they are fit to drive. The disclaimer
is shown during onboarding and must be accepted before tracking.
```

---

## Part 2 — Internal

### If the reviewer still cites 5.1.1(v)

5.1.1(v) permits requiring an account where account-based features are
significant. Concrete, checkable facts to point at, in descending strength:

| Claim | Where it lives |
|---|---|
| Report generation refuses unauthenticated calls | `functions/index.js` — `requestReport` throws `unauthenticated` when `request.auth` is absent; App Check enforced |
| Free-tier report quota is metered per account server-side | `functions/report-service.js` via `generateReport({ uid, … })` |
| Pro entitlement is verified against the account | `verifyPurchase(signedTransaction, uid, …)`; the StoreKit `appAccountToken` is derived from the uid (`FirebaseManager.appAccountToken`) |
| History is per-account cloud storage, not a local cache | `FirebaseManager.pullUserData()` restores events, entries, drink types, challenges, profile and coach reports from `users/{uid}/…` |
| In-app account deletion exists (5.1.1(v) also requires this) | Profile → Account → Delete Account → `deleteAccount` function |

What **not** to argue: the BAC maths itself runs on-device, so do not claim the
calculator needs the network. The defence is sync + server-side AI + entitlement,
not the calculation.

### Why 1.0.1 was rejected under 2.1(a), in one paragraph

Sign-up created the user, mailed the verification link, then signed the session
out so the account could not be used before verification. `AppState` treated
that internal sign-out as a user sign-out: it cleared local data and raised the
full-screen auth gate, which from the outside looked exactly like "the login
page reloads". Fixed in 1.0.2 (commit `9f0451f`) by distinguishing a real
sign-out (`userDidSignOut`) from the verification flow's internal one, and by
giving the gate a "Not now" exit so a failed sign-in can never trap the app.

### Pre-submission checklist

- [ ] Demo account exists, its email is **verified**, and sign-in with it was
      tested on a clean install of the exact build being submitted.
- [ ] Demo account has finished nights in the last 30 days — the non-Pro history
      view only shows the last 30 days, so older seed data looks like an empty app.
- [ ] Demo email and password typed into App Store Connect's **Sign-In
      Information** fields — never into this file or anywhere else in the repo,
      which is public.
- [ ] The EULA link is present in the App Store description as well as here
      (the 1.0.0 rejection was for its absence in the description).
- [ ] Backend and Firestore rules for this build are deployed before submitting
      (see `docs/RELEASE.md`) — reports fail against the old rules.
- [ ] Decide how the reviewer experiences Pro. In production
      `APPLE_ALLOW_SANDBOX=false`, so a sandbox subscription does **not** grant
      paid backend access: a reviewer who subscribes still generates reports on
      the free monthly allowance. In-app Pro screens unlock normally because
      that is driven by local StoreKit. Low risk while the free allowance is 5
      reports/month, but confirm the reviewer cannot land on a quota error after
      paying.
