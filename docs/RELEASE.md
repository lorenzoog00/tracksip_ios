# Release steps

## What changed

The app now calls authenticated, App Check protected Firebase functions for AI
reports and account deletion. **Uploading the iOS app alone is insufficient:**
deploy the matching backend and rules before distributing this build.
Older clients' direct report writes will be rejected by the new rules.

### One-time configuration

1. In Apple Developer, enable App Attest for `com.lorenzoog.siptrack` and refresh
   the app provisioning profile. The Release entitlement uses production App Attest.
2. In Firebase App Check, register the iOS app with App Attest and the Apple team
   ID. Debug builds use Firebase's debug provider; register development debug
   tokens only for development. Do not disable enforcement for production.
3. Obtain an **In-App Purchase API key** in App Store Connect. This is not assumed
   to be the same key as the existing GitHub upload key. Set secrets from a secure
   terminal; do not commit private keys:

   ```powershell
   cd functions
   npx firebase login
   npx firebase functions:secrets:set CLAUDE_API_KEY --project YOUR_PROJECT_ID
   npx firebase functions:secrets:set APPLE_IAP_PRIVATE_KEY --project YOUR_PROJECT_ID
   ```

4. Supply the deployment parameters when Firebase prompts, or in an ignored
   `functions/.env.YOUR_PROJECT_ID` file:

   ```dotenv
   APPLE_IAP_KEY_ID=your_iap_key_id
   APPLE_IAP_ISSUER_ID=your_issuer_uuid
   APPLE_APP_ID=your_numeric_app_store_id
   APPLE_ALLOW_SANDBOX=false
   ```

   Use a staging project with `APPLE_ALLOW_SANDBOX=true` for TestFlight purchase
   testing. Sandbox purchases do not grant paid backend access when false.
   Existing purchases without an app-account token bind to the first verified
   account that submits them; a second account cannot reuse that binding.

### Validate and deploy

```powershell
cd functions
npm ci
npm run lint
npm test
# Requires Java 21+; uses demo-siptrack, never production data.
npm run test:emulator
npm audit --omit=dev
npx firebase deploy --only functions,firestore:rules --project YOUR_PROJECT_ID
```

Delete the retired functions (`generateNightReport`, `generateRecoveryBrief`,
`generateCoachReport`) when deployment prompts. They are replaced by
`requestReport` and `deleteAccount`. Do not leave the old triggers deployed:
legacy pending documents must not trigger unrestricted model requests.
Deploy during a controlled rollout; existing clients cannot use their old report
or client-only deletion flows once the rules change.

There is no client write access to quotas, jobs, purchase ownership, or report
results. The owner can still sync ordinary event/profile/drink/challenge data.
Request metadata is validated; model calls have a timeout and bounded retries.
Failed requests consume quota because a provider may have already incurred cost.
Per report: at most three attempts. Concurrent requests share one claim.
Requests interrupted by a process failure become retryable after 150 seconds.

Free monthly limits: 5 night reports, 5 recovery briefs, 5 weekly reports,
1 monthly report, and 5 comparisons. Pro allows 300 reports total per UTC month;
all accounts have a 30-report UTC daily ceiling. The app discloses the Pro limits.
Quotas are server-owned and cannot be reset through the profile.

Deletion recursively removes all user collections, including recoveries and jobs,
then deletes Firebase Auth. A server-only `account_deletions/{uid}` marker remains
to reject late writes and still-valid old tokens. Purchase-owner mappings are
removed. Do not delete the marker during an in-flight deletion or token lifetime.
If deletion fails, the account remains blocked from writes and deletion can be
retried after signing in. Confirm the retry operationally in staging.

### Xcode / App Store Connect

1. Run the macOS CI workflow, including the entitlement regression test. The
   TestFlight workflow now requires CI success for its own source revision.
2. Open `siptrack.xcodeproj`; select the `siptrack` scheme, generic iOS device,
   then Product > Archive. Archives use Release. Local StoreKit files stay in
   the project for tests and are excluded from app resources.
3. On a real device verify: sign-in with each provider, cancellation and success
   of account deletion, purchases/restore/refund/expiry, ad consent and privacy
   choices, AI opt-in/off, quota errors/retry, Watch, widgets, and Live Activities.
4. Update App Store privacy answers and the hosted privacy policy to cover Firebase,
   Anthropic report processing, Apple purchase verification, and App Check.
   AI processing is disabled until the user enables it in Profile.
5. Validate the archive in Organizer and upload to App Store Connect. No upload or
   production deployment is performed by this cleanup.

## Dependencies

Apple's official server library is required to verify the certificate chain,
bundle/environment, and current purchase status with Apple. Firebase App Check
comes from the existing Firebase Swift package. The JavaScript rules-testing and
Firebase CLI packages are development-only. Unused `firebase-functions-test` was
removed. The `gaxios` UUID override keeps its existing v4 usage on a patched,
CommonJS-compatible UUID release; emulator and production dependency checks pass.

## References

- [Apple purchase verification library](https://github.com/apple/app-store-server-library-node)
- [Firebase App Attest setup](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- [Firebase callable protocol](https://firebase.google.com/docs/functions/callable-reference)
- [Google consent and privacy options](https://developers.google.com/admob/ios/privacy)
- [Apple privacy data identifiers](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)
- [NIAAA guidance on alcohol and driving](https://www.niaaa.nih.gov/publications/brochures-and-fact-sheets/truth-about-holiday-spirits)
