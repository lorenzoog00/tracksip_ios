# Unit economics — what a user costs and what they bring in

All figures per **active user per month**, at 20 MXN to the USD (the same rate
`functions/report-policy.js` prices the AI caps at — change it in both places).

The cost side is measured from this repository and Apple's own pricing. The ad
column is an industry range, not TrackSip data, and is marked as such. Do not
quote the ad numbers to anyone as if they were measured.

---

## Cost

| Item | Free user | Pro user | Where the number comes from |
|---|---|---|---|
| AI, realistic | **0.07 MXN** | **0.58 MXN** | measured prompts × plausible use |
| AI, at the caps | **0.19 MXN** | **10.73 MXN** | measured prompts × `report-policy.js` caps |
| Firestore | ~0 | ~0 | Free tier covers it — see below |
| Cloud Functions | ~0 | ~0 | A few dozen invocations; inside the free tier |

Two numbers per user, because the gap between them is wide and the honest
planning figure is the realistic one. The cap is what you are *insured* for.

### What one call costs

Measured by building each prompt from a full night's payload, rather than
assuming the priced ceiling. Output is at its enforced `max_tokens`, so it is a
true ceiling; input is what the prompt actually renders.

| Call | Input | Output | Cost |
|---|---|---|---|
| Night report | 656 tok | 700 tok | 0.83 ¢ |
| Recovery brief | 606 tok | 700 tok | 0.82 ¢ |
| Weekly | 619 tok | 700 tok | 0.82 ¢ |
| Monthly | 632 tok | 700 tok | 0.83 ¢ |
| Comparison | 781 tok | 700 tok | 0.86 ¢ |
| Drink lookup | 240 tok | 200 tok | 0.25 ¢ |

**One night costs 1.65 ¢**, because finishing a night fires two calls: the
night report and the recovery brief (`FirebaseManager.swift:400` and `:452`).
A drink lookup costs a third of a report — it sends a shorter prompt and asks
for 200 output tokens instead of 700.

### Why the free and paid ceilings differ so much

A **free** user is held by `FREE_LIMITS` to 26 calls a month: 5 night, 5
recovery, 5 weekly, 1 monthly, 5 comparison, 5 lookup. Spending every one of
them costs **0.19 MXN**. That ceiling is enforced in code, not by good
behaviour.

A **Pro** user has no per-kind limit at all. The only brake is the shared
monthly ceiling of **1300 calls**, which is the 15 MXN budget expressed in
calls. What 1300 calls cost depends on what they are:

| 1300 Pro calls spent on | Cost |
|---|---|
| Drink lookups | 3.25 MXN |
| Nights (650 of them) | 10.73 MXN |
| The priced worst case `spend.test.js` asserts | 14.30 MXN |

650 nights in a month is 21 a day. Nobody reaches it; the 150-a-day cap would
spread it over at least nine days. The realistic heavy Pro user — a night every
single day, plus weekly and monthly reports and ten lookups — spends 77 calls
and costs **0.58 MXN**.

### Per 1,000 installs

Assuming 30% become monthly-active and 5% of those subscribe:

    285 active free × 0.071 MXN  =  20.2 MXN
     15 Pro         × 0.58  MXN  =   8.7 MXN
                                    ─────────
                                      29 MXN/month   (~US$1.45)

Against 510 MXN from those 15 subscribers, **AI is 5.7% of revenue**.

For AI to cost 1,000 MXN a month you need roughly **34,000 installs**. At
100,000 installs it is ~2,900 MXN against ~51,000 MXN of subscription revenue.

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

**This is the first wall, not the AI bill.** 500 daily actives arrives long
before 34,000 installs — somewhere between 1,500 and 5,000 installs depending
on retention. Plan the read budget before the token budget.

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

**The lifetime tier is not for sale.** `com.lorenzoog.siptrack.pro.lifetime`
exists in `PRODUCTS` and in `Siptrack.storekit`, so the backend would honour
one if it ever existed, but nothing is selling it. That is the right call for
now: a one-time $59.99 is ~1,020 MXN net, and a user at the adversarial ceiling
below would spend that in about four years with no renewal to recover it. Every
other tier renews faster than any ceiling can eat it. Re-read this section
before enabling it.

### The ad column is a guess, and should stay labelled as one

AdMob has served **zero impressions** for this app, so there is no eCPM to
read. Any number here is an industry range for a utility app, and the real
figure will not be known until the app is live and the store listing is linked.

What can be said without data is the **break-even point**, because the cost
side is known:

    A free user at their ceiling costs 0.19 MXN ≈ $0.0095 a month.
    At a $1 eCPM that is about 10 ad impressions a month.

Ten impressions a month per user is a low bar, and the realistic free user
costs a third of that. The free tier should pay for itself comfortably — but
confirm it with real AdMob numbers before relying on it in any plan.

---

## What it means

| | |
|---|---|
| Margin on a realistic Pro user | ~34 MXN in, ~0.58 MXN out — **98%** |
| Margin on a Pro user at the cap | ~34 MXN in, ~10.73 MXN out — **68%** |
| One Pro user pays for | ~**179 free users** at their cost ceiling |
| Firestore starts costing money at | ~**500 daily active users** |
| Break-even on a free user | ~**10 ad impressions/month** |
| AI reaches 1,000 MXN/month at | ~**34,000 installs** |

The shape of this business is healthy: serving is cheap and bounded by code,
and a small paid share covers a large free base. The risk is not cost per user
— it is conversion and retention, which this table cannot tell you about.

### What the caps do and do not guarantee

All of the above holds **because the caps hold**, and the caps are enforced
rather than assumed. `functions/spend.test.js` fails the build if the configured
caps could exceed the per-user budget, and — since the input ceiling turned out
to be a number nobody checked — it also fails if the largest payload
`validateRequest` accepts can build a prompt over `MAX_PROMPT_CHARS`, or if the
largest *legitimate* prompt grows into that ceiling's headroom. Keep both.

**One gap is known and accepted.** The prompt ceiling counts characters,
because tokenisation cannot be reproduced server-side. The 3-characters-per-
token conversion is pessimistic for Latin text and wrong for emoji and for CJK
scripts, where one character can cost two or three tokens. A user who names
their drinks with emoji can push a report to roughly 4,900 input tokens while
staying under the 6,000-character ceiling:

| | |
|---|---|
| Fixed part of a night prompt | 3,313 chars |
| Left for user-supplied drink names | 2,687 chars (seven names) |
| If filled with emoji | ~1,343 emoji ≈ 3,500–4,900 input tokens |
| What the budget prices | 2,000 input tokens |

That makes the adversarial ceiling **21.70 MXN** rather than 14.30 — above the
15 MXN budget, and 64% of a monthly subscriber's net. It is still profitable,
it needs deliberate abuse plus 650 reports to reach, and it was judged not
worth fixing before launch. The fix, if it ever matters, is to cap a drink name
to 60 characters server-side as the client already does for model-supplied
names: seven 60-character names is ~630 tokens of emoji, which brings the total
back under 2,000.

**There is no global circuit breaker.** Every cap is per user. A bug that loops
reports is bounded for each account and unbounded in aggregate — 10,000 users
at the nightly ceiling would be ~107,000 MXN in a month. Unlikely, but nothing
in the code would stop it.
