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
   PRO_TESTER_UIDS=
   ```

   Use a staging project with `APPLE_ALLOW_SANDBOX=true` for TestFlight purchase
   testing. Sandbox purchases do not grant paid backend access when false.

   `PRO_TESTER_UIDS` is the way to test paid behaviour on TestFlight against
   *this* project without turning sandbox verification on for everybody. A
   TestFlight subscription is a sandbox purchase, so with `APPLE_ALLOW_SANDBOX`
   false the server cannot verify it and the tester falls to the free tier —
   paid screens unlocked by local StoreKit, five night reports from the
   backend, and a "limit reached" with no visible cause. List the Firebase uids
   (comma or whitespace separated) that should be billed as paid:

   ```dotenv
   PRO_TESTER_UIDS=uid_one,uid_two
   ```

   It grants the paid *quota tier* only. The daily and monthly ceilings still
   apply, so a listed uid cannot cost more than any paying user, and no
   `purchase_owners` entry is written because there is no transaction to bind.
   Matching is on the whole uid, and an empty value grants nothing. Find a uid
   in Firebase Console → Authentication, or in the app's own account screen.
   Leave it empty unless you are actively testing.
   Existing purchases without an app-account token bind to the first verified
   account that submits them; a second account cannot reuse that binding.

5. For the lock-screen BAC to update while the app is asleep, create an **APNs
   key** in Apple Developer → Certificates, IDs & Profiles → Keys (enable Apple
   Push Notifications service, environment "Sandbox & Production"). This is not
   the In-App Purchase key. Store the `.p8` as a secret with `--data-file` (the
   interactive prompt truncates multi-line keys) and add its Key ID to the
   `.env` file:

   ```powershell
   npx firebase functions:secrets:set APNS_AUTH_KEY --data-file C:\path\AuthKey_XXXXXXXXXX.p8 --project YOUR_PROJECT_ID
   ```

   ```dotenv
   APNS_KEY_ID=XXXXXXXXXX
   ```

   `syncLiveActivity` stores each night's projected curve in `live_activities/{uid}`
   and `pushLiveActivities` pushes the current value every 5 minutes. Without the
   key the lock screen still works but only updates when the app runs.

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

The live project is `device-streaming-8326abff` ("Tracksip" in the Firebase
console). The auto-generated name is not a scratch project: its project number
matches `GCM_SENDER_ID` in the committed `GoogleService-Info.plist`, which is
what the shipped app talks to. CI does not substitute that plist.

Two things that stop a first deploy on Windows:

- **`Error: User code failed to load ... Timeout after 10000`** is the function
  discovery step, not your code. Raise the limit:
  `$env:FUNCTIONS_DISCOVERY_TIMEOUT=120` before deploying.
- **Both secrets are required to deploy *any* function in this codebase**, even
  `--only functions:deleteAccount`, because `requestReport` declares them. Set a
  multi-line key from the file — the interactive prompt truncates it at the first
  newline: `firebase functions:secrets:set APPLE_IAP_PRIVATE_KEY --data-file
  AuthKey_XXXX.p8`. The non-secret params belong in an ignored
  `functions/.env.<project-id>` file.

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

## Friends / social release checklist

Friends v1 adds 11 callable functions, new Firestore rules and indexes, avatar
uploads and a report alert. **CI never deploys functions or indexes**, so none of
this ships with the app build: do every step below before distributing it. All of
it is done by the developer with their own credentials.

1. **Firebase project `device-streaming-8326abff`** (the live one, "Tracksip" in
   the console). In Google Cloud Console for that project, enable the **Cloud
   Vision API** (avatar SafeSearch runs on it).
2. Make sure the **default Storage bucket exists** (Firebase Console → Storage →
   Get started). Avatar uploads fail without it.
3. Deploy rules, indexes and functions together:

   ```powershell
   cd functions
   $env:FUNCTIONS_DISCOVERY_TIMEOUT=120
   npx firebase deploy --only firestore:rules,firestore:indexes,functions --project device-streaming-8326abff
   ```

   `firestore.indexes.json` declares the `blocked.uid` collection-group index and
   the `shared_nights.expires_at` TTL policy. **A missing `blocked.uid` index makes
   `deleteAccount` fail in production**, because deletion queries who blocked the
   user. The TTL policy is what actually deletes expired shared nights.
4. Confirm all 11 new callables exist (the secrets from "One-time
   configuration" above are still required to deploy):

   ```powershell
   npx firebase functions:list --project device-streaming-8326abff
   ```

   Expect `claimUsername`, `searchUsers`, `sendFriendRequest`,
   `respondToFriendRequest`, `cancelFriendRequest`, `removeFriend`, `blockUser`,
   `unblockUser`, `reportUser`, `setAvatar` and `registerPushToken`. A shipped
   callable that is missing from this list is a 404 in the app.
5. **Report alert.** In Google Cloud Console → Logging → Log-based alerts, create
   an alert on log text `SOCIAL_REPORT` (the `reportUser` function logs it) that
   emails the developer. We act on reports within 24 hours, as Apple asks of apps with
   user-generated content.
   Test it by filing a report from a test account.
6. **App Privacy and privacy policy.** In App Store Connect → App Privacy add:
   **Photos or Videos** (the profile photo). The username is a handle, covered by
   the existing **User ID**; drink and BAC data shared with friends stays under
   **Health** (also shared with other users). All linked to the user, not used for
   tracking, purpose App Functionality. State in the privacy policy (https://looqs.online/siptrack/policy)
   that drink and BAC data of a night is shared with the user's friends for 24
   hours (unless incognito), that profile photos are checked by Google Cloud
   Vision SafeSearch, and that account deletion removes friendships, requests,
   blocks, avatar and shared nights. `PrivacyInfo.xcprivacy` is already updated.
7. **Two-account TestFlight QA.** Use two real devices or accounts, A and B:
   1. Both claim a username.
   2. A sends B a request; B accepts. A push arrives on both sides.
   3. A starts a night: B sees it live in the feed with a matching BAC.
   4. A turns incognito on mid-night: the night disappears from B's feed.
   5. A turns incognito off, then ends a normal night: it moves to "Last 24
      hours" on B.
   6. B blocks A: search and feed are empty both ways.
   7. Delete account A: B's friends list no longer shows A.
   8. Report a user from the friends list, search results and incoming requests,
      once by username and once by photo; the `SOCIAL_REPORT` email arrives.

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
