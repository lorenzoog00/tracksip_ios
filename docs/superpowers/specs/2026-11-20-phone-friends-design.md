# Find friends by phone, and invite the rest

Status: draft for review. Date: 2026-11-20.

## Why

Contact matching today works by email. People in Mexico almost never save
emails in their contacts, so "In your contacts" finds nobody. The owner wants
growth to be organic, the BeReal way: you see which friends already have
TrackSip, and you invite the rest yourself, one tap per friend.

Success: a new user who adds their number sees friends from their phone book
on the search screen, and can send a WhatsApp invite to anyone who isn't on
TrackSip yet in two taps.

## Goals

1. A user can add a phone number to their account, confirmed by an SMS code.
   It is optional and can be skipped.
2. "In your contacts" matches the phone numbers in the user's contacts against
   verified TrackSip numbers.
3. An **Invite** list shows the contacts who aren't on TrackSip. Tapping Invite
   opens WhatsApp on that person's chat with a ready-made message and the
   user's TrackSip link.
4. Friends of friends keeps working exactly as today.
5. Email contact matching is removed completely: code, copy, privacy strings.
6. A Google Cloud cost alert warns the owner if SMS spending jumps.

## Non-goals

- Signing in with a phone number. The number is added to an existing Apple,
  Google or email account; the sign-in screen does not change. (Firebase will
  technically accept the number as a sign-in method once it's linked; we just
  don't offer it in the UI.)
- Our server sending SMS or WhatsApp messages to people who aren't users.
  Invites always go from the user's own WhatsApp or Messages.
- Storing anyone's contact list. Numbers are matched and dropped, as emails
  are today.
- Showing a user's number to other users. Nobody can see anyone's number.

## Anti-goals (would make this a failure even if it works)

- Social becomes unusable without a number. Skipping must leave Social working.
- The app texts people or nags them repeatedly. One prompt in onboarding, one
  prompt after the update, then only a small card on the search screen.
- An SMS bill nobody notices.

## Decisions made with the owner

- **Verification provider: Firebase phone auth.** Checked prices on
  2026-11-20 (cloud.google.com/identity-platform/pricing): Mexico $0.05 per
  SMS, US/Canada/Colombia $0.01, Spain $0.04, Chile $0.03, Argentina $0.09;
  the first 10 SMS per day are free. Every SMS sent is billed, including
  resends and codes never typed. Twilio Verify came to roughly $0.20 per
  Mexican verification.
- **All countries open.** No SMS region allowlist. App Check on our functions
  does not protect SMS sending (`verifyPhoneNumber` calls Identity Toolkit
  directly), so the only guard is Firebase's own APNs/reCAPTCHA check that
  the request comes from a real iPhone, with the cost alert as the alarm. If
  abuse shows up, the owner blocks those regions in the Firebase console or
  turns on App Check enforcement for Firebase Authentication; no app update.
- **Number entry:** a country picker with flags (all countries, searchable),
  then the national number. The digit count and format are checked per
  country (Mexico: 10 digits).
- **Invite via wa.me.** The Invite button opens
  `https://wa.me/<number>?text=<message>`.
- **Skipping keeps Social.** Without a number a user keeps the feed, username
  search, friends of friends, reactions and comments. They lose "In your
  contacts" and the Invite list, which are replaced by a card: "Add your
  number to find friends from your contacts."
- **Email matching is deleted**, not kept alongside.
- **Cost alert in Google Cloud.**

## Approaches considered

1. **Firebase phone auth, matched through Firebase Auth (chosen).** Firebase
   sends the code and links the number to the current account. Matching asks
   Firebase Auth which accounts own a list of numbers (`getUsers` with
   `phoneNumber` identifiers, 100 per call), exactly as `lookupVerifiedEmails`
   does for emails today. No new collection of phone numbers to protect or
   delete; Firebase already guarantees one account per number.
2. **Twilio Verify plus our own number index.** More control over limits and
   message wording, but about four times the cost in Mexico, another vendor
   with keys and a bill, and a Firestore collection of phone numbers we would
   have to secure and clean up on account deletion. Rejected on cost and
   surface area.
3. **Hashed numbers on our side.** Looks private but isn't: phone numbers
   are few enough that a hash is reversed by brute force in minutes. Adds
   complexity for no real protection. Rejected.

## How it works

### 1. Adding a number

**Screen "Add your number"** (one view, reused in three places):

```
        Find your friends
  TrackSip has a social side: see friends' nights,
  react and comment. Add your number to find
  friends from your contacts. It's never shown
  to anyone.

  [🇲🇽 +52 ▾] [ 55 1234 5678            ]

            [ Send code ]
              Not now
```

- The country button opens a searchable list of all countries: flag, name,
  dial code. Default: the phone's region (`Locale.current.region`), else
  Mexico.
- The number field formats as you type in that country's format. "Send code"
  stays disabled until the number is valid for the chosen country.
- **Code step:** a 6-digit field with the iOS one-time-code autofill
  (`textContentType(.oneTimeCode)`), a "Resend code" link that unlocks after
  30 seconds, and "Change number". On success: a short check animation and
  the screen closes.
- Errors, in plain words:
  - wrong code: "That code isn't right. Check the SMS and try again."
  - expired code: "That code expired. We sent you a new one." (only if the
    user tapped Resend; otherwise "Tap Resend for a new code.")
  - number on another account (`credentialAlreadyInUse`): "This number
    already belongs to another TrackSip account."
  - too many attempts (`tooManyRequests`): "Too many tries. Try again later."
  - no network: the app's usual offline message.

**Where it appears:**

1. **Onboarding**, right after "I Understand — Continue" on the disclaimer.
   New flow: profile fields → disclaimer → Add your number → app.
   "Not now" goes straight into the app.
2. **Existing users after the update**, the first time they open the Social
   tab with a username and without a number. Shown once per account per
   phone. "Not now" is remembered (local, keyed by uid) and never shown again.
3. **On demand**, from the "Add your number" card on the search screen and
   from the Social profile.

**Mechanics (iOS):** `PhoneAuthProvider.provider().verifyPhoneNumber(_:)`
returns a verification id; the code plus that id make a credential; then
`Auth.auth().currentUser.link(with:)`. When the user already has a number and
changes it, use `updatePhoneNumber(_:)` instead of `link`. After success,
force-refresh the ID token so the server sees the new number.

Firebase setup the app needs:
- Phone provider enabled in Firebase Authentication.
- The app already registers for remote notifications, which Firebase uses for
  its silent check. Its fallback is a reCAPTCHA web page, which needs the
  app's **encoded app ID** added as a URL scheme in Info.plist.
- No region allowlist (all countries).

**Social profile, "Phone number" row:** shows the number (formatted, only to
its owner) with **Change** and **Remove**. Remove unlinks the phone provider;
the contacts section goes back to the "Add your number" card.

### 2. "In your contacts" (by phone)

**On the phone:**
- Read contacts' phone numbers (`CNContactPhoneNumbersKey`) plus names
  (needed for the Invite list).
- Normalize each number to international format (E.164, e.g.
  `+525512345678`) with **PhoneNumberKit** (Swift package, libphonenumber
  data). Numbers without a country code take the country of the user's own
  verified number. Numbers that don't parse are dropped.
- Send at most **2,000** unique numbers per check (up from 500 emails).
- Requires: a verified number on the account, a Social username, and contacts
  permission. Without a number the check isn't offered at all.

**On the server, `matchContacts`:**
- Accepts `{phones: string[]}`; each must match `^\+[1-9]\d{6,14}$`. Payloads
  over 5,000 entries are refused; past 2,000 clean numbers the rest are
  ignored.
- Refuses a caller whose ID token has no `phone_number`
  (`failed-precondition`, "Add your number first.").
- Looks up owners with `auth.getUsers` using `{phoneNumber}`, 100 per call,
  skipping disabled accounts. Everything after the lookup stays as it is
  today: drop self, blocked both ways and existing friends, return Social
  profiles, nudge matched people with the existing "@x is on TrackSip" and
  "create your profile" pushes (max one per person per day, never twice
  about the same sender, at most 30 per call).
- **Returns the matched numbers too**, so the phone can leave them out of the
  Invite list. A user who matched but has no Social profile is still never
  revealed to the caller: their number comes back in an `on_tracksip` list
  without uid or name, only so the phone stops offering to invite them.
  (Answer to: "is it OK to tell the caller that this number has TrackSip?"
  It reveals one bit, and only for numbers already in the caller's own
  contacts, rate limited. Accepted; see Review Focus.)
- Rate limit stays at **2 checks per account per day**.

**Caching (fixes the "checked your contacts a lot today" bug):** the result
is saved on the phone for the day, per account, so reopening the app or the
screen reuses it instead of spending a check. A new check runs only when the
saved result is from another day, or the user pulls to refresh (which spends
a check). When the server says the limit is reached, the app shows the saved
result if there is one; otherwise: "You've already checked today. Your
results will be here tomorrow." — never the raw server error.

### 3. Invite list

On the search screen ("You might know"), below "In your contacts" and
"Friends of friends":

```
  Invite to TrackSip                     [🔍]
  ( A ) Ana López            [ Invite ]
  ( B ) Beto                 [ Invite ]
  ...
```

- Built **on the phone**: contacts with at least one valid number, minus
  numbers that matched (Social or `on_tracksip`), minus the user's own
  number. Sorted A–Z by name, with a search field. One row per contact (the
  first valid mobile number, else the first valid number).
- Shows the first 30 rows and a "Show all" button, so the screen doesn't turn
  into a phone book.
- **Invite** opens `https://wa.me/<digits>?text=<message>` (digits = E.164
  without the `+`). If WhatsApp isn't installed (`canOpenURL("whatsapp://")`,
  which needs `whatsapp` in `LSApplicationQueriesSchemes`), it opens the
  Messages composer with the same text instead. After returning, the button
  reads **Invited** for that contact (local, for 7 days).
- Message (Spanish when the phone's language is Spanish, English otherwise):
  - ES: "¡Únete a TrackSip! Agrégame: @<username> https://tracksip.online/u/<username>"
  - EN: "Join me on TrackSip! Add me: @<username> https://tracksip.online/u/<username>"
  The link is the existing friend link (`FriendLink.shareURL`), which opens
  the app or the App Store.
- Without a number: the Invite list is hidden too (it depends on the match
  result to avoid inviting people who already have TrackSip).

### 4. Removing email matching

- Delete `ContactEmails`, `cleanEmails`, `lookupVerifiedEmails`,
  `CONTACT_EMAILS_MAX` and the email path of `matchContacts`. Old builds
  calling `matchContacts` with `emails` get `failed-precondition` with
  "Update TrackSip to find friends from your contacts." (The app already has
  a forced/soft update flow; no extra work.)
- Copy: "Only email addresses are checked..." becomes "Only phone numbers are
  checked, and nothing is saved."
- `NSContactsUsageDescription`: "Find friends who already use TrackSip and
  invite the rest. Phone numbers are checked and never saved."

### 5. Account deletion

Deleting the Firebase Auth user already removes the linked number. Nothing
new is stored, so the existing cleanup (`contact_nudges`,
`contact_match_limits`) is enough.

### 6. Cost alert

A Google Cloud **budget** on the billing account of project
`device-streaming-8326abff`, scoped to Identity Platform / Firebase Auth SMS,
at **$20 per month**, with emails at 50%, 90% and 100%. Budgets alert, they
don't stop spending. Created with `gcloud billing budgets create` if the
account has billing permissions, otherwise the owner clicks through
Billing → Budgets & alerts (steps written in docs/RELEASE.md).

### 7. Paperwork that must change

- **App Store privacy labels** (owner, in App Store Connect): add "Phone
  Number — linked to the user, used for app functionality". Contacts stays
  "not collected" since nothing is stored, matching today's answer.
- **docs/APP-REVIEW-NOTES.md**: replace the email paragraph with the phone
  flow; the demo account must work without a number (skip).
- **Privacy policy** at tracksip.online/policy: phone number collected for
  friend finding, contacts' numbers checked and not stored. Lives in the
  EMporium web repo.

## Rollout order

1. Enable the Phone provider and the URL scheme; create the budget.
2. Deploy the functions. The email path is gone at once, with no transition
   period: old builds get the "Update TrackSip" message. Accepted because
   email matching found almost nobody anyway.
3. Ship the app build; update privacy labels and the policy before submitting
   for review.

## Review Focus (cases no happy-path test covers)

1. Mexican numbers in every saved form all become `+525512345678`:
   `55 1234 5678`, `5512345678`, `+52 55 1234 5678`, `+52 1 55 1234 5678`,
   `044 55 1234 5678`, `(55) 1234-5678`.
2. A contact saved without a country code when the user's own number is from
   another country (a US user with a Mexican friend saved as `55 1234 5678`)
   — it matches as US or not at all, never crashes.
3. The number is already on another account (`credentialAlreadyInUse`): clear
   message, the current account is unchanged.
4. A matched user without a Social profile never appears by name or uid in the
   caller's response; only their number in `on_tracksip`.
5. Limit reached with and without a saved result for today; app relaunch the
   same day spends no check.

## Calls made after the builder check (owner can overrule)

1. **What `on_tracksip` contains:** every matched number except the caller's
   own. That includes friends, people blocked either way, and accounts without
   a Social profile. Numbers only, never a uid or name. This keeps friends and
   existing users out of the Invite list. The leak is one bit ("this number
   in your contacts has an account"), the same bit already accepted above.
   Blocked people still never appear as profiles.
2. **"Has a number"** is read on the phone from `currentUser.phoneNumber`.
   The post-update prompt's "Not now" is stored locally per uid, so a
   reinstall asks once more. That's acceptable.
3. **Number already on another account:** shown as an error only, with the
   hint "If it's your other account, sign in there and remove it under
   Social → Phone number." There's no moving a number between accounts.
4. **Phone-auth plumbing the app lacks today:**
   - add `remote-notification` to `UIBackgroundModes`;
   - pass the APNs token to `Auth.auth().setAPNSToken` and incoming pushes to
     `Auth.auth().canHandleNotification` (no reliance on swizzling);
   - forward opened URLs to `Auth.auth().canHandle(url)`;
   - add the encoded-app-ID URL scheme.

   **Owner step:** upload the APNs auth key (.p8) under Firebase console →
   Project settings → Cloud Messaging, so the silent check works. Without it,
   every user gets the reCAPTCHA web page.
5. **More than one provider per account:** the builder audits sign-out,
   re-authentication before account deletion
   (`requiresPasswordReauth(providerIDs:)`) and the Apple token revoke,
   now that a phone provider can sit next to Apple, Google or password. A
   phone provider must never be chosen as the re-auth method.
6. **Stale token after Remove:** `matchContacts` checks the live record
   (`auth.getUser(uid).phoneNumber`), not the token claim. That's one extra
   read per check.
7. **Cache window:** the saved result is valid for 24 hours from the check,
   matching the server's rolling window, not the calendar day. Changing or
   removing the number clears it.
8. **Normalization rules:** the default region is the country of the user's
   own number. For Mexico, `044`/`045` prefixes are stripped, and `+52 1` plus
   10 digits becomes `+52` plus the 10 digits. Anything PhoneNumberKit can't
   parse as valid is dropped. **PhoneNumberKit** (Swift Package) is added as
   a dependency.
9. **Payload:** contacts are de-duplicated, mobile numbers come first, then
   enumeration order, and only the first 2,000 are kept. The server runs the
   `getUsers` batches at most 5 at a time, within the existing 60 s timeout.
10. **Invite fallbacks:**
    - WhatsApp → Messages composer → the share sheet with the same text, when
      the device can't send texts (iPad, Simulator).
    - "Invited" is set when WhatsApp opens or the composer reports *sent*.
      iOS can't confirm a WhatsApp send.

## Left to the builder

- Exact layout, animation and copy polish within the screens sketched above,
  following the existing Social look.
- How the "Invited" marks and the day cache are stored locally.
- Splitting the work into tasks and tests.
