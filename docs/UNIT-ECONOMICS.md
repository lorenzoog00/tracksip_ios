# Unit economics — what a user costs and what they bring in

All figures per **active user per month**, at 20 MXN to the USD (the same rate
`functions/report-policy.js` prices the AI caps at — change it in both places).

Two of the four inputs are measured from this repository and Apple's own
pricing; the ad column is an industry range, not TrackSip data, and is marked
as such. Do not quote the ad numbers to anyone as if they were measured.

---

## Cost

| Item | Free user | Pro user | Where the number comes from |
|---|---|---|---|
| AI reports | **0.23 MXN** | **3.30 MXN** | `report-policy.js`, worst case at the caps |
| Firestore | ~0 | ~0 | Free tier covers it — see below |
| Cloud Functions | ~0 | ~0 | A few dozen invocations; inside the free tier |
| **Total** | **~0.23 MXN** | **~3.30 MXN** | |

### Why the AI numbers differ so much

They are both worst cases, but the caps differ. A **free** user is limited by
`FREE_LIMITS` to 21 reports a month (5 night, 5 recovery, 5 weekly, 1 monthly,
5 comparison). A **Pro** user is limited by the shared ceiling of 300 a month.

So a free user cannot cost more than about a quarter of a peso, however hard
they try. That ceiling is enforced in code, not by good behaviour.

Per report, worst case: 2,000 input + 700 output tokens on `claude-haiku-5-5`
at $0.10 / $0.50 per million = **$0.00055**, about 0.011 MXN.

### Why Firestore rounds to zero

Firestore's free tier is **50,000 document reads, 20,000 writes and 20,000
deletes per day**, plus 1 GiB stored. Reads bind first: the app pulls the
user's data on launch, so budget roughly 100 reads per user per day.

    50,000 reads/day ÷ 100 per user ≈ 500 daily active users, free

Below that, the database costs nothing. Above it the unit prices live in the
Cloud Platform SKU list, but the order of magnitude stays far under the AI
line — reads are priced per hundred thousand, and AI is priced per report.

**The thing to watch is reads, not storage.** `pullUserData()` fetches events,
entries, drink types, challenges, the profile and the coach reports on every
sign-in. If daily actives pass ~500, cache locally and pull deltas before
anything else.

---

## Revenue

| Source | Gross | Apple's cut | Net to you |
|---|---|---|---|
| Pro monthly | $1.99 | 15% | **$1.69 ≈ 34 MXN/mo** |
| Pro yearly | $19.99 | 15% | **$16.99 ≈ 340 MXN/yr ≈ 28 MXN/mo** |
| Ads (free user) | — | — | **unknown — see below** |

The 15% assumes the **App Store Small Business Program** (under $1M a year).
If you are not enrolled, Apple takes 30% and monthly net falls to $1.39 ≈ 28
MXN. Enrolling is worth doing before launch; it is an application in App Store
Connect, not an automatic benefit.

### The ad column is a guess, and should stay labelled as one

AdMob has served **zero impressions** for this app, so there is no eCPM to
read. Any number here is an industry range for a utility app, and the real
figure will not be known until the app is live and the store listing is linked.

What can be said without data is the **break-even point**, because the cost
side is known:

    A free user costs 0.23 MXN ≈ $0.012 a month.
    At a $1 eCPM that is about 12 ad impressions a month.

Twelve impressions a month per user is a low bar. The free tier should pay for
itself comfortably — but confirm it with real AdMob numbers before relying on
it in any plan.

---

## What it means

| | |
|---|---|
| Margin on a Pro user | ~34 MXN in, ~3.30 MXN out — **over 90%** |
| One Pro user pays for | ~**150 free users** at their cost ceiling |
| Firestore starts costing money at | ~**500 daily active users** |
| Break-even on a free user | ~**12 ad impressions/month** |

The shape of this business is healthy: serving is cheap and bounded by code,
and a small paid share covers a large free base. The risk is not cost per user
— it is conversion and retention, which this table cannot tell you about.

### The one number that could break it

All of the above holds **because the caps hold**. `functions/spend.test.js`
fails the build if the configured caps could exceed the per-user budget, so
raising a limit or changing the model cannot quietly change these economics.
Keep that test.
