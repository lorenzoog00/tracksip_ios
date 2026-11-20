# Find Friends by Phone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace email contact matching with phone matching: optional SMS-verified number, "In your contacts" by phone, and a WhatsApp Invite list.

**Architecture:** Firebase phone auth links a number to the existing account. `matchContacts` looks numbers up in Firebase Auth (`getUsers` with `phoneNumber`) and returns Social profiles plus the matched numbers. The phone normalizes contacts with PhoneNumberKit, caches the result for 24 h, and builds the Invite list locally.

**Tech Stack:** SwiftUI (iOS 18), FirebaseAuth (firebase-ios-sdk 12.x), PhoneNumberKit 4.x (SPM), Contacts, MessageUI; Cloud Functions v2 (Node 24).

**Spec:** docs/superpowers/specs/2026-11-20-phone-friends-design.md

## Global Constraints

- iOS 18, Swift 5 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure helpers are `nonisolated static` so Swift Testing suites can call them synchronously.
- Every new Swift file needs four `project.pbxproj` entries (PBXBuildFile, PBXFileReference, group `children`, target Sources phase), with fresh unique 24-hex IDs, for the app target and, for tests, the `siptrackTests` target. An unregistered test file silently never runs.
- Tests: Swift Testing (`import Testing`, `@testable import siptrack`, `@MainActor struct XTests`), in `siptrackTests/`.
- There is no local Xcode. Swift compiles only in CI (`gh workflow run ci.yml --ref feat/phone-friends`). Write Swift carefully; the controller runs CI.
- Functions: eslint google style, 80 columns, JSDoc on every function, LF line endings. `cd functions && npm run lint && npm test && npm run test:emulator`.
- Commit messages: a single line, no body (a hook rejects multi-line messages).
- App UI copy is English. The only Spanish string is the Spanish invite message.
- Phone format everywhere between phone and server: E.164, matching `^\+[1-9]\d{6,14}$`.
- Constants: `CONTACT_PHONES_MAX = 2000`, `CONTACT_PAYLOAD_MAX = 5000`, `CONTACT_CALLS_PER_DAY = 2` (unchanged), `getUsers` batches of 100 run at most 5 at a time, contact cache valid 24 h, "Invited" mark lasts 7 days, the Invite list shows 30 rows before "Show all", Resend unlocks after 30 s, 6-digit codes.
- A user's number is never shown to anyone but its owner, and never stored in Firestore by us.

## Review Focus

1. Mexican numbers in every saved form (`55 1234 5678`, `5512345678`, `+52 55 1234 5678`, `+52 1 55 1234 5678`, `044 55 1234 5678`, `(55) 1234-5678`) all become `+525512345678`. Pinned in Task 2.
2. A contact saved without a country code, for a user whose own number is from another country: normalized with the user's region or dropped, never a crash. Pinned in Task 2.
3. A matched account without a Social profile is never in `results`, only its number in `on_tracksip`. Pinned in Task 1.
4. Limit reached with and without a fresh cached result; relaunching the same day spends no check. Pinned in Task 5 (`ContactMatchCache` tests).
5. A password account that links a phone must not become a "usable session" while its email is unverified. Pinned in Task 3.

---

### Task 1: `matchContacts` by phone (backend)

**Files:**
- Modify: `functions/social.js` (replace `cleanEmails`, the `CONTACT_EMAILS_MAX` constant and the email path of `matchContacts`; update `module.exports`)
- Modify: `functions/index.js` (replace `lookupVerifiedEmails` with `lookupPhoneOwners`, add `callerHasPhone`, wire both into `exports.matchContacts`)
- Test: `functions/integration/emulator.test.js` (rewrite the `contactsCall` helper and the contact tests around lines 1485–1600)

**Interfaces:**
- Produces: callable `matchContacts({phones: string[]})` → `{results: ProfileCard[] (each with in_contacts: true), on_tracksip: string[]}`.
- Produces: `social.matchContacts({db, uid, data, lookupPhones, hasPhone, notify, now})` where `lookupPhones(phones) => Promise<{uid: string, phone: string}[]>` and `hasPhone(uid) => Promise<boolean>`.
- Produces: export `CONTACT_PHONES_MAX` (2000), replacing `CONTACT_EMAILS_MAX`.

- [ ] **Step 1: Rewrite the contact tests for phones (failing)**

Change `contactsCall(uid, phones, {lookup, hasPhone, notify, now})` to pass `data: {phones}`, `lookupPhones: lookup || (async () => [])`, `hasPhone: hasPhone || (async () => true)`. Lookups now return `{uid, phone}` objects. Keep every existing behavior test, converted to numbers, and add:

```js
test("social: contacts return the matched numbers, never no-profile uids", async () => {
  // A has a profile; B on Social (friend), C on Social, D no profile, A self.
  // lookup returns B, C, D and A itself for +5255000000{1..4}.
  const {results, on_tracksip: onTrackSip} = await contactsCall("A", phones, {lookup});
  assert.deepEqual(results.map((r) => r.uid), ["C"]);       // B is a friend
  assert.deepEqual(onTrackSip.sort(),
      ["+525500000001", "+525500000002", "+525500000003"]);  // not A's own
  assert.ok(!JSON.stringify(results).includes("D"));
});
test("social: blocked people's numbers are in on_tracksip but not results", ...);
test("social: contact matching needs a verified number", async () => {
  await assert.rejects(contactsCall("A", ["+525512345678"], {hasPhone: async () => false}),
      (e) => e.code === "failed-precondition" && /Add your number first/.test(e.message));
  // and it does not spend a check: two more calls with a number still succeed.
});
test("social: old builds sending emails are told to update", async () => {
  await assert.rejects(social.matchContacts({...base, data: {emails: ["a@x.com"]}}),
      (e) => e.code === "failed-precondition" &&
        e.message === "Update TrackSip to find friends from your contacts.");
});
test("social: contact matching checks the first 2000 valid numbers", ...);
// junk and non-E.164 strings dropped; duplicates counted once; 5001 entries refused
// with invalid-argument; exactly 5000 accepted; a non-array refused.
```

- [ ] **Step 2: Run them to see them fail**

Run: `cd functions && npm run test:emulator`
Expected: the new phone tests FAIL (`lookupPhones` is not called, and no `on_tracksip` comes back).

- [ ] **Step 3: Implement `cleanPhones(value) -> string[]` and the new `matchContacts` in `functions/social.js`**

- `cleanPhones`: non-array → `invalid-argument` "Missing contacts."; length over `CONTACT_PAYLOAD_MAX` → `invalid-argument` "Too many contacts."; trimmed strings matching the E.164 regex, de-duplicated, first `CONTACT_PHONES_MAX`.
- Order inside `matchContacts`:
  1. If `data.phones` is missing and `data.emails` is present → `failed-precondition` "Update TrackSip to find friends from your contacts."
  2. `cleanPhones`.
  3. The profile and deletion checks (unchanged).
  4. `hasPhone(uid)` false → `failed-precondition` "Add your number first."
  5. The rate-limit transaction (unchanged).
  6. `lookupPhones`.
- `on_tracksip` = the phones of every looked-up owner except `uid`, taken before the friend/block/profile filtering. Everything after the lookup (results, nudges, push caps) keeps today's logic, keyed by `uid`.
- Update the JSDoc to say numbers are matched and dropped. Remove the email code and `EMAIL_PATTERN` if nothing else uses it.

- [ ] **Step 4: Implement `lookupPhoneOwners(phones)` and `callerHasPhone(uid)` in `functions/index.js`**

- `lookupPhoneOwners`: `getAuth().getUsers(batch.map((phoneNumber) => ({phoneNumber})))` in batches of 100, at most 5 batches in flight. Skip `disabled` users. Return `{uid, phone: user.phoneNumber}`.
- `callerHasPhone`: `Boolean((await getAuth().getUser(uid)).phoneNumber)`. This is the live record, not the token, so a removed number stops matching at once.
- Pass both as `lookupPhones` and `hasPhone`. Update the comment above `exports.matchContacts`.

- [ ] **Step 5: Run everything**

Run: `cd functions && npm run lint && npm test && npm run test:emulator`
Expected: all pass; lint clean.

- [ ] **Step 6: Commit**

```bash
git add functions/social.js functions/index.js functions/integration/emulator.test.js
git commit -m "Match contacts by verified phone number instead of email"
```

---

### Task 2: Phone number normalization and contact loading (iOS)

**Files:**
- Modify: `siptrack.xcodeproj/project.pbxproj`: add the Swift package `https://github.com/marmelroy/PhoneNumberKit` (upToNextMajorVersion from `4.0.0`), product `PhoneNumberKit`, linked to the `siptrack` app target only. Follow the existing `firebase-ios-sdk` entries' shape: XCRemoteSwiftPackageReference, XCSwiftPackageProductDependency, PBXBuildFile in Frameworks, the target's `packageProductDependencies`, and the project's `packageReferences`.
- Create: `SipTrack/Social/PhoneNumbers.swift`
- Create: `SipTrack/Social/ContactPhones.swift`
- Leave `enum ContactEmails` in `UserSearchView.swift` for now; Task 5 deletes it together with its callers.
- Test: `siptrackTests/PhoneNumbersTests.swift`, `siptrackTests/ContactPhonesTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct PhoneCountry: Identifiable, Hashable { let region: String; let name: String; let dialCode: Int; let flag: String; var id: String { region } }
  enum PhoneNumbers {
      nonisolated static func normalize(_ raw: String, defaultRegion: String) -> String?   // E.164 or nil
      nonisolated static func region(ofE164 number: String) -> String?                   // "MX"
      nonisolated static func e164(national: String, region: String) -> String?          // valid only
      nonisolated static func formatted(_ e164: String) -> String                        // "+52 55 1234 5678"
      nonisolated static func formattedPartial(_ typed: String, region: String) -> String // as-you-type
      static var countries: [PhoneCountry]                                                // all, sorted by name
      static var defaultRegion: String                                                    // Locale region if known, else "MX"
  }
  struct ContactEntry: Identifiable, Equatable { let id: String; let name: String; let phones: [String] } // E.164, mobile first
  enum ContactPhones {
      nonisolated static func load(defaultRegion: String) throws -> [ContactEntry]
      nonisolated static func phonesToCheck(_ entries: [ContactEntry], ownPhone: String?, limit: Int = 2000) -> [String]
      nonisolated static func invitable(_ entries: [ContactEntry], onTrackSip: Set<String>, ownPhone: String?) -> [ContactEntry]
      static var isAllowed: Bool   // .authorized or .limited
  }
  ```

- [ ] **Step 1: Write `PhoneNumbersTests` (failing)**

```swift
@Test func mexicanFormsAllNormalizeToTheSameNumber() {
    for raw in ["55 1234 5678", "5512345678", "+52 55 1234 5678", "+52 1 55 1234 5678",
                "044 55 1234 5678", "045 55 1234 5678", "(55) 1234-5678", "+521 5512345678"] {
        #expect(PhoneNumbers.normalize(raw, defaultRegion: "MX") == "+525512345678", "\(raw)")
    }
}
@Test func usNumbersNormalize() {
    #expect(PhoneNumbers.normalize("(415) 555-2671", defaultRegion: "US") == "+14155552671")
    #expect(PhoneNumbers.normalize("+1 415 555 2671", defaultRegion: "MX") == "+14155552671")
}
@Test func nationalNumberUsesTheUsersRegionOrIsDropped() {
    // A US user with a Mexican friend saved without +52: read as US, invalid there → nil.
    #expect(PhoneNumbers.normalize("55 1234 5678", defaultRegion: "US") == nil)
}
@Test func junkIsDropped() {
    for raw in ["", "abc", "123", "+", "++52551234", String(repeating: "9", count: 40)] {
        #expect(PhoneNumbers.normalize(raw, defaultRegion: "MX") == nil)
    }
}
@Test func e164FromNationalChecksTheCountry() {
    #expect(PhoneNumbers.e164(national: "5512345678", region: "MX") == "+525512345678")
    #expect(PhoneNumbers.e164(national: "551234567", region: "MX") == nil)   // 9 digits
}
@Test func regionOfE164() { #expect(PhoneNumbers.region(ofE164: "+525512345678") == "MX") }
@Test func countriesIncludeMexicoWithFlagAndDialCode() {
    let mx = PhoneNumbers.countries.first { $0.region == "MX" }
    #expect(mx?.dialCode == 52); #expect(mx?.flag == "🇲🇽")
}
```

- [ ] **Step 2: Write `ContactPhonesTests` (failing)**

```swift
@Test func phonesToCheckTakesEachContactsFirstNumberFirst() {
    let e = [ContactEntry(id: "1", name: "Ana", phones: ["+521", "+522"]),
             ContactEntry(id: "2", name: "Beto", phones: ["+523"])]
    #expect(ContactPhones.phonesToCheck(e, ownPhone: nil, limit: 2) == ["+521", "+523"])
}
@Test func phonesToCheckDropsOwnNumberAndDuplicates() { ... }   // own excluded; same number in two contacts sent once
@Test func invitableLeavesOutMatchedOwnAndNumberless() {
    // Ana matched (+521 in onTrackSip) → out; Beto own number → out; Caro no phones → out; Dani → in.
}
@Test func invitableIsSortedByNameIgnoringCaseAndAccents() { /* "ángel", "Beto", "carla" order */ }
```

(Use realistic E.164 strings; the short ones above only show shape.)

- [ ] **Step 3: Implement `PhoneNumbers` in `SipTrack/Social/PhoneNumbers.swift`**

- Use one shared `PhoneNumberUtility` (PhoneNumberKit 4.x).
- Mexico pre-pass before parsing: strip a leading `044`/`045` from national input; rewrite `+52 1` / `521` followed by 10 digits to `+52` plus the 10 digits.
- Accept only numbers PhoneNumberKit validates. Flags come from regional-indicator scalars. Country names come from `Locale.current.localizedString(forRegionCode:)`.

- [ ] **Step 4: Implement `ContactPhones` in `SipTrack/Social/ContactPhones.swift`**

- `load` enumerates `CNContactFetchRequest` with given name, family name, nickname, organization and phone numbers, using `.userDefault` sort order.
- `name` is "given family", falling back to nickname, then organization, then the formatted first number.
- Phones are normalized and de-duplicated per contact. Ones labelled `CNLabelPhoneNumberMobile`/`CNLabelPhoneNumberiPhone` come first.
- Contacts with no valid number are skipped.
- Off the main thread (callers use `Task.detached`).

- [ ] **Step 5: Register the 4 new files in project.pbxproj, add the package, and commit**

```bash
git add SipTrack/Social/PhoneNumbers.swift SipTrack/Social/ContactPhones.swift siptrackTests/PhoneNumbersTests.swift siptrackTests/ContactPhonesTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "Add PhoneNumberKit, phone normalization and contact phone loading"
```

---

### Task 3: Phone verification in FirebaseManager, plus Auth plumbing

**Files:**
- Modify: `Firebase/FirebaseManager.swift`
- Modify: `SipTrack/Core/PushRegistration.swift` (`AppDelegate`)
- Modify: `SipTrack/SipTrackApp.swift` (`onOpenURL`)
- Modify: `SipTrack/Info.plist`
- Test: `siptrackTests/AuthSessionTests.swift` (extend), create `siptrackTests/PhoneAuthErrorTests.swift`

**Interfaces:**
- Produces on `FirebaseManager`:
  ```swift
  @Published private(set) var phoneNumber: String?          // auth.currentUser?.phoneNumber, kept current
  func sendPhoneCode(to e164: String) async throws -> String // verification id
  func confirmPhoneCode(_ code: String, verificationID: String) async throws // link, or updatePhoneNumber if one exists; then force-refresh the ID token
  func removePhoneNumber() async throws                     // unlink provider "phone"
  nonisolated static func phoneErrorMessage(code: Int) -> String?  // AuthErrorCode raw value → copy; nil = use friendlyAuthError
  ```

- [ ] **Step 1: Write failing tests**

```swift
// AuthSessionTests
@Test func phoneDoesNotMakeAnUnverifiedPasswordAccountUsable() {
    #expect(FirebaseManager.isUsableSession(providerIDs: ["password", "phone"], isEmailVerified: false) == false)
    #expect(FirebaseManager.isUsableSession(providerIDs: ["apple.com", "phone"], isEmailVerified: false) == true)
}
@Test func phoneNeverChangesTheReauthMethod() {
    #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["password", "phone"]) == true)
    #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["apple.com", "phone"]) == false)
}
// PhoneAuthErrorTests
@Test func phoneErrorCopy() {
    #expect(FirebaseManager.phoneErrorMessage(code: AuthErrorCode.invalidVerificationCode.rawValue)
        == "That code isn't right. Check the SMS and try again.")
    #expect(FirebaseManager.phoneErrorMessage(code: AuthErrorCode.sessionExpired.rawValue)
        == "That code expired. Tap Resend for a new code.")
    #expect(FirebaseManager.phoneErrorMessage(code: AuthErrorCode.credentialAlreadyInUse.rawValue)
        == "This number already belongs to another TrackSip account. If it's your other account, sign in there and remove it under Social → Phone number.")
    #expect(FirebaseManager.phoneErrorMessage(code: AuthErrorCode.tooManyRequests.rawValue)
        == "Too many tries. Try again later.")
    #expect(FirebaseManager.phoneErrorMessage(code: AuthErrorCode.invalidPhoneNumber.rawValue)
        == "That number doesn't look right.")
    #expect(FirebaseManager.phoneErrorMessage(code: AuthErrorCode.networkError.rawValue) == nil)
}
```

- [ ] **Step 2: Implement in `FirebaseManager.swift`**

- `isUsableSession` ignores `"phone"` when deciding whether a non-password provider vouches for the account.
- Audit `reauthenticate`: it must never pick `phone`.
- `phoneNumber` is set in `applySession` and after link, update or unlink.
- `sendPhoneCode` uses `PhoneAuthProvider.provider().verifyPhoneNumber(e164, uiDelegate: nil)`.
- `confirmPhoneCode` builds `PhoneAuthProvider.provider().credential(withVerificationID:verificationCode:)`. It calls `user.link(with:)` when `user.phoneNumber == nil`, otherwise `user.updatePhoneNumber(_:)`, then `getIDTokenForcingRefresh(true)`.
- Errors thrown to callers are mapped by the views with `phoneErrorMessage(code:)` falling back to `friendlyAuthError`.

- [ ] **Step 3: Auth plumbing**

- `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken`: call `Auth.auth().setAPNSToken(deviceToken, type: .unknown)` first. Upload the token to our server (`registerPushToken`) **only** when notification permission is authorized, checked with `PushRegistration.isAuthorized` on the current settings. Today the upload is unconditional, but registration only ever happened after permission, so behavior is unchanged.
- Add `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`: if `Auth.auth().canHandleNotification(userInfo)`, complete with `.noData`; otherwise `.noData` too. No other remote handling exists here.
- `didFinishLaunching`: add `application.registerForRemoteNotifications()` unconditionally. iOS gives a token without asking the user, which Firebase phone auth needs for its silent check. Keep the existing `registerIfAuthorized` call.
- `SipTrackApp.onOpenURL`: first `if Auth.auth().canHandle(url) { return }`, before the Google handler.
- `Info.plist`:
  - add `remote-notification` to `UIBackgroundModes`, keeping `fetch`;
  - add a `CFBundleURLTypes` entry whose scheme is the encoded app ID: `GOOGLE_APP_ID` from `GoogleService-Info.plist` with `:` replaced by `-`, prefixed `app-` (e.g. `app-1-438688245872-ios-…`).

- [ ] **Step 4: Register the new test file, commit**

```bash
git add Firebase/FirebaseManager.swift SipTrack/Core/PushRegistration.swift SipTrack/SipTrackApp.swift SipTrack/Info.plist siptrackTests/AuthSessionTests.swift siptrackTests/PhoneAuthErrorTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "Verify and link a phone number with Firebase phone auth"
```

---

### Task 4: "Add your number" screen and where it appears

**Files:**
- Create: `SipTrack/Views/Social/AddPhoneView.swift`
- Create: `SipTrack/Views/Social/CountryPickerView.swift`
- Create: `SipTrack/Social/PhonePrompt.swift`
- Modify: `SipTrack/Views/Onboarding/OnboardingView.swift` (disclaimer accept → AddPhoneView → `completeOnboarding()`)
- Modify: `SipTrack/Views/Social/SocialRootView.swift` (one-time prompt on the feed)
- Modify: `SipTrack/Views/Social/SocialProfileView.swift` ("Phone number" row)
- Test: `siptrackTests/PhonePromptTests.swift`

**Interfaces:**
- Consumes: `PhoneNumbers`, `PhoneCountry` (Task 2); `FirebaseManager.sendPhoneCode/confirmPhoneCode/removePhoneNumber/phoneNumber/phoneErrorMessage` (Task 3).
- Produces:
  ```swift
  struct AddPhoneView: View { init(onFinish: @escaping (_ added: Bool) -> Void) }
  enum PhonePrompt {
      nonisolated static func shouldPrompt(hasPhone: Bool, hasUsername: Bool, dismissed: Bool) -> Bool
      static func isDismissed(uid: String) -> Bool        // UserDefaults "phonePromptDismissed.<uid>"
      static func markDismissed(uid: String)
  }
  ```
- Produces for Task 5: `FriendsStore.clearContactCache()` is called after a number is added, changed or removed. Declare it as a no-op stub here if Task 5 hasn't landed; Task 5 fills it in.

- [ ] **Step 1: `PhonePromptTests` (failing)**: `shouldPrompt` is true only for `(hasPhone: false, hasUsername: true, dismissed: false)`. Check all eight combinations.

- [ ] **Step 2: Implement `PhonePrompt`, `CountryPickerView`, `AddPhoneView`**

- Layout and copy are the spec's sketch, verbatim: title "Find your friends", the body text, "Send code", "Not now".
- Country button: flag + `+<dialCode>`. It opens `CountryPickerView`, a searchable list over name and dial code, defaulting to `PhoneNumbers.defaultRegion`.
- "Send code" is enabled only when `PhoneNumbers.e164(national:region:)` is non-nil.
- Code step:
  - a 6-digit field with `.textContentType(.oneTimeCode)` and `.keyboardType(.numberPad)`;
  - it auto-submits on the 6th digit;
  - "Resend code" is disabled for 30 s, with a countdown;
  - "Change number" goes back.
- On success: a checkmark animation (scale and fade, about 0.6 s, with the app's success haptic if one exists), then `onFinish(true)`. "Not now" → `onFinish(false)`.
- Follow the app's existing look: `AppColors`, rounded 14 pt accent buttons like `SocialProfileView`'s "Share profile".

- [ ] **Step 3: Placements**

- **Onboarding:** `DisclaimerView`'s accept presents `AddPhoneView`. Its `onFinish` calls `completeOnboarding()` and, when a uid exists, `PhonePrompt.markDismissed(uid:)`, so Social doesn't ask again.
- **SocialRootView:** on the feed's appear, when `PhonePrompt.shouldPrompt(hasPhone: firebase.phoneNumber != nil, hasUsername: friends.myProfile != nil, dismissed: PhonePrompt.isDismissed(uid:))`, present `AddPhoneView` as a sheet. Present it only when no push-opened thread or friend-link sheet is pending, so it never stacks on them. `onFinish(false)` marks dismissed. `onFinish(true)` also marks dismissed.
- **SocialProfileView:** a "Phone number" row showing `PhoneNumbers.formatted(number)`, or "Add your number" when there is none.
  - **Change** opens `AddPhoneView`.
  - **Remove** asks with a confirmation dialog: "Remove your number? Friends won't find you from their contacts." It then calls `removePhoneNumber()`.
  - Both call `friends.clearContactCache()` on success.

- [ ] **Step 4: Register the 4 new files, commit**

```bash
git add SipTrack/Views/Social/AddPhoneView.swift SipTrack/Views/Social/CountryPickerView.swift SipTrack/Social/PhonePrompt.swift siptrackTests/PhonePromptTests.swift SipTrack/Views/Onboarding/OnboardingView.swift SipTrack/Views/Social/SocialRootView.swift SipTrack/Views/Social/SocialProfileView.swift siptrack.xcodeproj/project.pbxproj
git commit -m "Ask for a phone number after the disclaimer, once in Social, and from the Social profile"
```

---

### Task 5: Contacts by phone, the 24-hour cache, and the Invite list

**Files:**
- Create: `SipTrack/Social/ContactMatchCache.swift`
- Create: `SipTrack/Social/Invite.swift`
- Create: `SipTrack/Views/Social/MessageComposer.swift` (a `UIViewControllerRepresentable` around `MFMessageComposeViewController`)
- Modify: `Firebase/FirebaseManager.swift` (`matchContacts(phones:)`)
- Modify: `SipTrack/Social/FriendsStore.swift` (replace the session-only cache)
- Modify: `SipTrack/Views/Social/UserSearchView.swift`
- Modify: `SipTrack/Info.plist` (`LSApplicationQueriesSchemes` += `whatsapp`; new `NSContactsUsageDescription`)
- Test: `siptrackTests/ContactMatchCacheTests.swift`, `siptrackTests/InviteTests.swift`

**Interfaces:**
- Consumes: `ContactPhones`, `ContactEntry`, `PhoneNumbers` (Task 2); `FirebaseManager.phoneNumber` (Task 3); `AddPhoneView` (Task 4).
- Produces:
  ```swift
  struct ContactMatchResult: Codable, Equatable { var profiles: [FriendProfileSnapshot]; var onTrackSip: Set<String> }
  // FriendProfileSnapshot: Codable mirror of FriendProfile (uid, username, photoURL, avatarColor)
  struct ContactMatchCache: Codable, Equatable {
      var result: ContactMatchResult; var checkedAt: Date; var ownerPhone: String
      nonisolated static func isFresh(_ cache: ContactMatchCache?, now: Date, currentPhone: String?) -> Bool  // < 24 h and same phone
      static func load(uid: String) -> ContactMatchCache?   // UserDefaults "contactMatch.<uid>"
      static func save(_ cache: ContactMatchCache, uid: String)
      static func clear(uid: String)
  }
  enum Invite {
      nonisolated static func message(username: String, spanish: Bool) -> String
      nonisolated static func whatsAppURL(phone e164: String, message: String) -> URL?
      nonisolated static func isInvited(at date: Date?, now: Date) -> Bool   // within 7 days
      static func markInvited(contactID: String, uid: String)              // UserDefaults "invited.<uid>"
      static func invitedAt(contactID: String, uid: String) -> Date?
  }
  // FirebaseManager
  func matchContacts(phones: [String]) async throws -> ContactMatchResult
  // FriendsStore
  func contactMatches(phones: [String]) async throws -> ContactMatchResult   // saves the cache for this uid
  func cachedContactMatches() -> ContactMatchResult?                         // fresh cache only
  func clearContactCache()
  ```

- [ ] **Step 1: Write failing tests**

```swift
@Test func cacheIsFreshFor24HoursWithTheSamePhone() {
    let c = ContactMatchCache(result: .init(profiles: [], onTrackSip: []), checkedAt: t0, ownerPhone: "+525512345678")
    #expect(ContactMatchCache.isFresh(c, now: t0 + 23 * 3600, currentPhone: "+525512345678"))
    #expect(!ContactMatchCache.isFresh(c, now: t0 + 24 * 3600, currentPhone: "+525512345678"))
    #expect(!ContactMatchCache.isFresh(c, now: t0 + 60, currentPhone: "+14155552671"))  // number changed
    #expect(!ContactMatchCache.isFresh(c, now: t0 + 60, currentPhone: nil))             // number removed
    #expect(!ContactMatchCache.isFresh(nil, now: t0, currentPhone: "+525512345678"))
}
@Test func cacheRoundTripsThroughJSON() { /* encode → decode equals */ }
@Test func inviteMessages() {
    #expect(Invite.message(username: "lalo", spanish: true)
        == "¡Únete a TrackSip! Agrégame: @lalo https://tracksip.online/u/lalo")
    #expect(Invite.message(username: "lalo", spanish: false)
        == "Join me on TrackSip! Add me: @lalo https://tracksip.online/u/lalo")
}
@Test func whatsAppURLUsesDigitsAndEncodesText() {
    let url = Invite.whatsAppURL(phone: "+525512345678", message: "¡Hola! @lalo https://tracksip.online/u/lalo")
    #expect(url?.absoluteString.hasPrefix("https://wa.me/525512345678?text=") == true)
    #expect(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        == "¡Hola! @lalo https://tracksip.online/u/lalo")
}
@Test func invitedLastsSevenDays() {
    #expect(Invite.isInvited(at: t0, now: t0 + 6 * 86400))
    #expect(!Invite.isInvited(at: t0, now: t0 + 7 * 86400))
    #expect(!Invite.isInvited(at: nil, now: t0))
}
```

The link must use `FriendLink.shareURL(for:)`. The test strings assume that returns `https://tracksip.online/u/<username>`.

- [ ] **Step 2: Implement `ContactMatchCache`, `Invite`, `MessageComposer`; `FirebaseManager.matchContacts(phones:)`**

- `matchContacts(phones:)` parses `results` as today, plus `on_tracksip` into a `Set`.
- Delete `matchContacts(emails:)` and `enum ContactEmails`.
- `FriendProfileSnapshot` lives in `ContactMatchCache.swift`, with `init(_ profile: FriendProfile)` and `var profile: FriendProfile`.

- [ ] **Step 3: `FriendsStore`**

- Replace `contactMatchesThisSession`/`contactMatchesOwner` with `ContactMatchCache` keyed by the current uid.
- `contactMatches(phones:)` saves only if the uid is unchanged when the call returns, as today.
- `cachedContactMatches()` returns the result only when `isFresh(…, currentPhone: FirebaseManager.shared.phoneNumber)`.
- `clearContactCache()` clears for the current uid. Replace Task 4's stub if one exists.

- [ ] **Step 4: `UserSearchView`**

- **No number:** the contacts card becomes "Add your number to find friends from your contacts". Tapping it opens `AddPhoneView`, and success starts a check. Hide the Invite list.
- **With a number and contacts allowed:**
  - Use a fresh cache when there is one. Otherwise check automatically, as today.
  - Load `ContactPhones.load(defaultRegion: region of own number)` off the main thread. Send `phonesToCheck`.
  - `resource-exhausted`: show the cached result if any; otherwise "You've already checked today. Your results will be here tomorrow." Never the raw message.
  - `.refreshable` on the list runs a new check, which spends one.
- **Card copy:** subtitle "Only phone numbers are checked, and nothing is saved." The empty result reads "None of your contacts are on TrackSip yet. Invite them below."
- **Sections in order:**
  1. "In your contacts" (unchanged rows);
  2. friends of friends (unchanged);
  3. "Invite to TrackSip": `ContactPhones.invitable(entries, onTrackSip:, ownPhone:)` with a search field filtering by name. The first 30 rows, then "Show all (N)". Each row is an initial avatar, the name and an **Invite** button, or **Invited** (disabled look) when `Invite.isInvited`.
- **Invite tap:**
  - `UIApplication.shared.canOpenURL(URL(string: "whatsapp://")!)` → open `Invite.whatsAppURL` and mark invited.
  - Else if `MFMessageComposeViewController.canSendText()` → `MessageComposer` with recipient and body, marked invited only on `.sent`.
  - Else a share sheet with the message.
  - The message's language: Spanish when `Locale.preferredLanguages.first` starts with "es".
- **Info.plist:**
  - `NSContactsUsageDescription` = "Find friends who already use TrackSip and invite the rest. Phone numbers are checked and never saved."
  - add `LSApplicationQueriesSchemes` with `whatsapp`.

- [ ] **Step 5: Register the 5 new files, commit**

```bash
git add SipTrack/Social/ContactMatchCache.swift SipTrack/Social/Invite.swift SipTrack/Views/Social/MessageComposer.swift Firebase/FirebaseManager.swift SipTrack/Social/FriendsStore.swift SipTrack/Views/Social/UserSearchView.swift SipTrack/Info.plist siptrackTests/ContactMatchCacheTests.swift siptrackTests/InviteTests.swift siptrack.xcodeproj/project.pbxproj
git commit -m "Find contacts by phone with a 24-hour cache and add a WhatsApp Invite list"
```

---

### Task 6: Docs, review notes and owner steps

**Files:**
- Modify: `docs/APP-REVIEW-NOTES.md`:
  - registration paragraph: phone number now optional, asked after the disclaimer, with "Not now";
  - Contacts paragraph: phone numbers only, matched over HTTPS against verified TrackSip numbers, not stored;
  - the demo account works without adding a number.
- Modify: `docs/RELEASE.md`: a "Phone friends — one-time setup" section with:
  1. Firebase console → Authentication → Sign-in method → Phone: Enable. No region policy.
  2. Firebase console → Project settings → Cloud Messaging → upload the APNs auth key (.p8), Key ID and Team ID.
  3. Google Cloud Billing → Budgets & alerts: budget "SMS phone auth", project `device-streaming-8326abff`, $20/month, alerts at 50/90/100%. Or the equivalent `gcloud billing budgets create` command with `--filter-projects` and the three `--threshold-rule` flags.
  4. App Store Connect privacy: add Phone Number (linked to user, App Functionality).
  5. Update tracksip.online/policy.
  6. Deploy order: functions first, then the app. Old builds then see "Update TrackSip to find friends from your contacts."

- [ ] **Step 1: Edit both docs as above**
- [ ] **Step 2: Commit**

```bash
git add docs/APP-REVIEW-NOTES.md docs/RELEASE.md
git commit -m "Document phone friend finding for review and the one-time setup"
```
