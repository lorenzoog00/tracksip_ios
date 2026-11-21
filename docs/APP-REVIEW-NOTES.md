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
rather than creating a new one. It is already email-verified and has several
completed nights logged, so there is real history in the app.

The demo account is a free account, not a subscriber. Stats, Calendar, AI Coach
and Challenges are Pro features and will show the paywall until you subscribe.
Subscribing in the sandbox as described below opens all four, with that logged
history already in them.

TrackSip uses email verification: a newly created email/password account cannot
sign in until the link we email has been opened. If you create a fresh account
with a throwaway address and do not open that link, sign-in will correctly
refuse and return you to the sign-in screen. "Sign in with Apple" is also
available and needs no verification step.

A previous build had a bug where signing up appeared to reload the sign-in
screen. That is fixed in this build.

TESTING THE SUBSCRIPTION

Sign in, then tap any locked feature (Calendar, Stats, AI Coach or Challenges)
on the home screen. The pricing screen appears; select a plan and tap Subscribe.

Tracksip Pro is an auto-renewable subscription. Payment is charged to your
Apple Account at confirmation of purchase and renews automatically unless
cancelled at least 24 hours before the end of the current period. Manage or
cancel in your Apple Account settings.

WHY TRACKSIP REQUIRES AN ACCOUNT (Guideline 5.1.1(v))

TrackSip's account-based features are core to the app, not incidental:

1. Cross-device history. A user's nights, drink entries, custom drinks,
   challenges and reports are stored per-account in Firestore and restored when
   they sign in on another device or after reinstalling. Drinking history is the
   product; losing it with the device would make the app useless.

2. Server-generated AI. The morning recovery plan (built from a morning
   check-in), weekly/monthly reviews and night-to-night comparisons are
   produced by our authenticated backend (a Firebase Cloud Function calling
   Anthropic's Claude API), not on the device. The function rejects
   unauthenticated calls, and the free monthly allowance (3 morning plans a
   month) is metered per account on the server. There is no way to offer this
   feature without an identified account.

3. Subscription entitlement. TrackSip Pro is bound to the account: the signed
   App Store transaction is verified server-side against the signed-in user, so
   a subscription follows the person across their devices and cannot be shared
   between accounts.

We ask for as little as possible. Registration takes an email address and
password, or Sign in with Apple, or Google — no contacts and no
social accounts are required. Sign in with Apple is offered first and works with Apple's
private relay addresses. After the disclaimer the app offers to add a phone
number so friends can find the user from their contacts; this is optional and
"Not now" skips it, so it is never needed to create an account or use the app. Body details used for the BAC estimate (sex, weight,
and optionally height and birth year) are entered after sign-in, are used only
for that calculation, and are not required to create the account.

Users can delete their account and all associated cloud data from inside the
app: Profile → Account → Delete Account.

MORNING CHECK-IN AND RECOVERY PLAN (AI)

The morning after a night with a few drinks, TrackSip offers a check-in: a
local notification (about 7 hours after the night ends, never before 8 AM, and
only if notifications are allowed) and a card on the home screen. The user
taps how they feel (headache, nausea, wrecked, dizzy, anxious, or fine) and
gets a short recovery plan: a few things to do right now, a breakfast and one
or two activities for the day, each with a photo and a one-line reason, and at
most one myth to skip. This replaces the night reports and next-morning
recovery briefs of earlier versions; nights that already have one keep
showing it. Free accounts get 3 plans a month; Pro is unlimited within
fair-use limits.

- Consent: a plan is only built when the user has turned on AI reports in
  Profile → AI Reports, whose text says that drink logs, BAC estimates, body
  measurements, night details and how they feel the morning after are sent to
  Anthropic. The check-in repeats this in one line under the tiles, at the
  moment of sending. The symptoms the user taps go to Anthropic under that
  consent, and to no one else.
- Photos: breakfast and activity photos come from a library we generate with
  Google's Gemini image model on Vertex AI. Only the dish or scene name and a
  fixed style description are sent to Google, never user data. New photos are
  reviewed by the developer before other users see them.
- No medical advice: the plan gives no medical advice or dosing. There is no
  diagnosis, and where it mentions a common painkiller it does so in general
  terms only, never with a dose. It never suggests more alcohol and never
  claims anything sobers you up faster. Two safety lines are added by the app
  itself, not by the AI: "don't drive this morning" whenever the BAC estimate
  is still above zero, and "get medical help" (with the warning signs) after a
  very heavy night.

SOCIAL (FRIENDS)

TrackSip has an optional Friends feature. Users pick a username, find people by
username, and send or accept friend requests. Accepted friends can see each
other's current night and nights closed in the last 24 hours (drinks and BAC
estimate). Nothing is public: only accepted friends see anything, data expires
24 hours after a night closes, and a user can switch on Incognito to share
nothing. There are no leaderboards and no rankings, and BAC is never compared or
ranked between users. Friends can react to a night with one of two fixed emojis (🍻 or 💧)
and leave short text comments on it; there is no private chat or direct
messaging.

User-generated content safeguards (Guideline 1.2):
- Report: every user (username or profile photo) can be reported from the
  friends list, search results and incoming requests. Reports email the
  developer. We act on reports within 24 hours, as Apple asks of apps with
  user-generated content.
- Block: any user can be blocked from the same places. Blocking removes the
  friendship and hides both users from each other in search and the feed.
- Photo filtering: profile photos are screened with SafeSearch on upload and
  rejected if adult, violent or racy.
- Friends can be removed at any time, and deleting the account removes all of
  the user's social data.
- Contacts (optional): in Find friends, "Find friends from your contacts"
  asks for Contacts access. Only the phone numbers are sent, over HTTPS, to
  check which belong to TrackSip accounts with a verified phone number; they
  are not stored or logged, and the check takes at most 2,000 numbers and runs
  at most twice a day (results are cached on the phone for 24 hours). Contacts
  not on TrackSip appear in an Invite list that opens WhatsApp or Messages
  (or the share sheet when neither is available) with a prefilled message the
  user sends themselves; TrackSip sends nothing to them. People found this way may get one notification that the user is on
  TrackSip. Nothing is read until the user taps the button and grants access.
- Phone number (optional): added after the disclaimer in onboarding (with "Not
  now"), once in Social for existing users, and changeable or removable in the
  Social profile. It is verified by SMS code through Firebase Authentication
  and used only so friends can find each other. It is never shown to other
  users. The demo account works without
  adding a number: skip the prompt with "Not now". To try it without a real
  SMS, use the test phone number and code written in App Store Connect's
  review notes.
- Reactions and comments on a night: reactions are a fixed set of two emojis (🍻 and 💧).
  Comments are text only, at most 200 characters, with no links or photos, and
  are rate-limited. Any comment can be reported with a long-press: the report
  stores a copy of that comment's text with its author and night (same
  reports pipeline and 24-hour response as above), and its author can be
  blocked; blocking hides reactions and comments in both directions and the
  server refuses new ones across a block. Authors delete their own comments
  and the night's owner can delete any comment on their night. Everything
  disappears with the night, 24 hours after it closes, and is deleted from
  the server within two days after that. @mentions only reach people
  who can already see that night, and each kind of notification (reactions,
  comments, replies and mentions) can be switched off in the Social profile.
- "You might know" also lists friends of the user's friends.

The demo account has one friend with a recent night, so the Social tab has
content to review.

Privacy Policy: https://tracksip.online/policy
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

ABOUT THE APP

Tracksip tracks alcohol consumption and estimates BAC using the Widmark
formula. Age rating 17+ due to alcohol content. The estimates are informational
only: the app is not a medical device, is not a substitute for a breathalyser,
and never tells anyone they are fit to drive. The disclaimer is shown during
onboarding and must be accepted before tracking.
```

> The version above is what is currently in the Notes field for 1.0. Keep the
> two in step: the subscription and age-rating paragraphs are there because
> Apple expects them, and pasting an older copy of this file would drop them.

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
- [ ] Demo account has one accepted friend (a second seeded account) whose
      night closed in the last 24 hours, or is live now: shared nights expire
      after 24 h, so re-seed that night right before each submission.
- [ ] Social backend (functions, indexes, TTL, Cloud Vision, report alert) is
      deployed per `docs/RELEASE.md` → "Friends / social release checklist".
- [ ] Demo account has finished nights in the last 30 days — the non-Pro history
      view only shows the last 30 days, so older seed data looks like an empty app.
- [ ] The notes match what the demo account actually is. A free demo account
      cannot show Stats, Calendar, AI Coach or Challenges: those are Pro-gated
      in `HomeView`, and claiming otherwise puts a false statement in front of
      App Review. The locked set is exactly those four — Drinks is not locked.
- [ ] Demo email and password typed into App Store Connect's **Sign-In
      Information** fields — never into this file or anywhere else in the repo,
      which is public.
- [ ] The EULA link is present in the App Store description as well as here
      (the 1.0.0 rejection was for its absence in the description).
- [ ] The **build attached to the version** is the one you mean. It is picked by
      hand and does not follow the newest upload: 1.0 sat with a build from six
      weeks earlier, which would have been reviewed instead of the fixes.
- [ ] Backend and Firestore rules for this build are deployed before submitting
      (see `docs/RELEASE.md`) — reports fail against the old rules.
- [ ] The Apple Developer Program License Agreement is accepted. When it is
      updated, submission is blocked until the Account Holder accepts it, and
      the only warning is a banner on the App Store Connect home page.
- [ ] Pro for the reviewer needs nothing prepared: they subscribe in the
      sandbox themselves. In production `APPLE_ALLOW_SANDBOX=false`, so that
      purchase cannot be verified server-side and they fall to the free monthly
      allowance, while the Pro screens unlock from local StoreKit. That is fine
      for a review. It was *not* fine before 2026-10-26: `verifyPurchase` threw
      instead of degrading, so the reviewer would have seen "Purchase could not
      be verified. Restore purchases and try again." seconds after subscribing.
      For a real Pro account without paying, use an App Store Connect offer
      code — it is a production transaction and verifies normally.
