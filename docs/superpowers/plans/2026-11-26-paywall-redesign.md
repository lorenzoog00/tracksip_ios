# Paywall Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the upgrade half of `ProView` with the "hangover plan first" paywall, without touching purchase, restore or entitlement logic.

**Architecture:** `ProView` stays the entry point (same `ProView(presentation:)` API, same `purchase()` and restore code) and keeps the Pro-member membership view. The free-user screen moves into a new presentational `PaywallScreen` that takes plain values (`PaywallPlanOption`s, selection, flags) and closures, so tests can render it without StoreKit or `AppState`. Pure copy and the feature catalog live in `PaywallCopy` / `PaywallFeatures` and are unit-tested. A rendering test writes PNGs at small and large iPhone widths and at the largest text size; CI uploads them as an artifact so the screen can be checked without a Mac.

**Tech Stack:** SwiftUI (iOS 18, Swift 5 mode, MainActor default isolation), StoreKit 2, Swift Testing, GitHub Actions macOS CI.

**Spec:** `docs/superpowers/specs/2026-11-24-paywall-redesign-design.md`

## Global Constraints

- UI copy in English. Prices only from StoreKit (`Product.displayPrice`, `priceFormatStyle`); never a hardcoded price.
- Guideline 1.4.3: no max/peak BAC, "most drinks", streaks, rankings, record night anywhere in paywall copy.
- Only real Pro features are listed as Pro; "Custom drinks" and "Watch" are free and never listed.
- Required on screen: price + billing period + renewal terms, Restore Purchases, Terms of Use (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`), Privacy Policy (`https://tracksip.online/policy`), a close button in the `.modal` presentation.
- `StoreManager` is not modified. `ProView.purchase()` and the restore closure keep today's bodies.
- Lifetime is not offered on the paywall (yearly + monthly only, yearly selected by default).
- Respect `accessibilityReduceMotion` and Dynamic Type up to `.accessibility5`. App is dark-only.
- New Swift files need four `project.pbxproj` entries each (PBXBuildFile, PBXFileReference, group child, Sources phase). Commit messages: one line, no body.

## Review Focus

1. Products fail to load or load empty: the spinner / "Try Again" states must still show, and no CTA with "—" as the price.
2. Only one of yearly/monthly loads: the screen shows the one that exists and selects it; the CTA never targets a missing product.
3. Largest text size on a 375 pt wide phone: nothing truncates the price or renewal terms; the bottom bar stops being pinned so it can't cover the screen.
4. Purchase in flight: both the CTA and plan cards ignore taps; the CTA shows progress.
5. A free-trial intro offer exists but the user already used it (`isEligibleForIntroOffer == false`): no trial copy anywhere.

---

### Task 1: Copy, feature catalog and trial model

**Files:**
- Create: `SipTrack/Views/Subscription/PaywallScreen.swift` (this task adds only the `// MARK: - Copy` section)
- Create: `siptrackTests/PaywallTests.swift`
- Modify: `siptrack.xcodeproj/project.pbxproj` (4 entries per new file: app file in the `Subscription` group next to `ProView.swift` and the app Sources phase; test file in the `siptrackTests` group and the test Sources phase, mirroring `MorningPlanDisplayTests.swift`)

**Interfaces:**
- Produces:
  - `struct PaywallTrial: Equatable { enum Unit { case day, week, month, year }; let value: Int; let unit: Unit; var adjective: String /* "3-day" */; var duration: String /* "3 days", "1 week" */ }`
  - `extension PaywallTrial { init?(offer: Product.SubscriptionOffer) }` — nil unless `offer.paymentMode == .freeTrial`
  - `struct PaywallFeature: Hashable { let icon: String; let title: String }`
  - `enum PaywallFeatures { static let pro: [PaywallFeature]; static let membership: [PaywallFeature] }`
  - `enum PaywallCopy` with `title`, `subtitle`, `allowance`, `alwaysFree`, `trust` (static strings), `static func savingsPercent(monthly: Decimal, yearly: Decimal) -> Int?`, `static func ctaLabel(period: SubscriptionPeriod, price: String, trial: PaywallTrial?) -> String`, `static func renewalTerms(period: SubscriptionPeriod, price: String, trial: PaywallTrial?) -> String`

Exact copy:
- `title` = "Wake up with a plan"
- `subtitle` = "After every night out, a recovery plan for how you actually feel."
- `allowance` = "Free: \(MorningCheckIn.freeMonthlyPlans) plans a month · Pro: every morning"
- `alwaysFree` = "Always free: live BAC, Live Activity, widgets and friends."
- `trust` = "BAC estimated with the Widmark formula."
- `PaywallFeatures.pro` (icon, title): ("sparkles", "AI Coach"), ("chart.bar.fill", "Stats"), ("calendar", "Calendar"), ("arrow.left.arrow.right", "Compare periods"), ("target", "Personal goals"), ("clock.arrow.circlepath", "Full history"), ("wand.and.stars", "AI drink lookup"), ("doc.text.fill", "PDF export"), ("eye.slash.fill", "No ads")
- `PaywallFeatures.membership` = [("sunrise.fill", "Recovery plan every morning")] + `pro`
- CTA, no trial: yearly "Continue · \(price)/yr", monthly "Continue · \(price)/mo", lifetime "Continue · \(price)". With trial: "Start your \(trial.adjective) free trial".
- Terms, no trial: "Auto-renews yearly at \(price) until canceled. Cancel anytime in Settings." (monthly: "monthly"). With trial: "\(trial.duration) free, then \(price) a year. Auto-renews until canceled. Cancel anytime in Settings." (monthly: "a month"). Lifetime: "One-time purchase. No subscription."
- `savingsPercent`: whole percent saved by yearly vs 12 × monthly, rounded down; nil when monthly ≤ 0 or the result ≤ 0.

- [ ] **Step 1: Write the failing tests** in `siptrackTests/PaywallTests.swift` (`@MainActor struct PaywallTests`, `import StoreKit`, `@testable import siptrack`):

```swift
@Test func savingsFloorsToWholePercent() {
    #expect(PaywallCopy.savingsPercent(monthly: Decimal(string: "1.99")!, yearly: Decimal(string: "19.99")!) == 16)
    #expect(PaywallCopy.savingsPercent(monthly: 2, yearly: 24) == nil)
    #expect(PaywallCopy.savingsPercent(monthly: 0, yearly: 10) == nil)
}
@Test func ctaNamesPriceAndPeriodWithoutTrial() {
    #expect(PaywallCopy.ctaLabel(period: .yearly, price: "$19.99", trial: nil) == "Continue · $19.99/yr")
    #expect(PaywallCopy.ctaLabel(period: .monthly, price: "$1.99", trial: nil) == "Continue · $1.99/mo")
}
@Test func ctaNamesTheTrial() {
    let trial = PaywallTrial(value: 3, unit: .day)
    #expect(PaywallCopy.ctaLabel(period: .yearly, price: "$19.99", trial: trial) == "Start your 3-day free trial")
}
@Test func renewalTermsStatePriceAndPeriod() {
    #expect(PaywallCopy.renewalTerms(period: .yearly, price: "$19.99", trial: nil)
            == "Auto-renews yearly at $19.99 until canceled. Cancel anytime in Settings.")
    #expect(PaywallCopy.renewalTerms(period: .monthly, price: "$1.99", trial: PaywallTrial(value: 1, unit: .week))
            == "1 week free, then $1.99 a month. Auto-renews until canceled. Cancel anytime in Settings.")
}
@Test func trialDurationsPluralize() {
    #expect(PaywallTrial(value: 3, unit: .day).duration == "3 days")
    #expect(PaywallTrial(value: 1, unit: .month).adjective == "1-month")
}
@Test func onlyRealProFeaturesAreListed() {
    let titles = PaywallFeatures.membership.map(\.title)
    #expect(titles.first == "Recovery plan every morning")
    #expect(!titles.contains { $0.localizedCaseInsensitiveContains("custom drink") || $0.localizedCaseInsensitiveContains("watch") })
}
@Test func copyAvoidsCompetitionWords() {
    let copy = [PaywallCopy.title, PaywallCopy.subtitle, PaywallCopy.allowance, PaywallCopy.alwaysFree, PaywallCopy.trust]
        + PaywallFeatures.membership.map(\.title)
    for banned in ["max", "peak", "streak", "rank", "record", "most drinks", "leaderboard"] {
        #expect(!copy.contains { $0.localizedCaseInsensitiveContains(banned) }, "\(banned)")
    }
}
```

- [ ] **Step 2: Implement the Copy section** in `PaywallScreen.swift` to the interfaces and copy above.
- [ ] **Step 3: Re-read every line for compile errors** (no local Xcode): exhaustive `switch` on `SubscriptionPeriod` (`.monthly`, `.yearly`, `.lifetime`) and on `Product.SubscriptionPeriod.Unit` with `@unknown default`; `Decimal` math via `NSDecimalNumber` for flooring.
- [ ] **Step 4: Commit** — `git commit -m "Add paywall copy, the real Pro feature list and trial wording, with tests"`

### Task 2: Hero assets and the sample plan preview

**Files:**
- Create: `SipTrack/Assets.xcassets/PaywallBreakfast.imageset/` (`paywall-breakfast.jpg` from library item `x-eggs-on-toast`), `PaywallWalk.imageset/` (`x-walk-daylight`), `PaywallNap.imageset/` (`x-nap-bed`); each `Contents.json` = one `universal` image, `info` author xcode version 1
- Modify: `SipTrack/Views/Subscription/PaywallScreen.swift` (add `// MARK: - Hero`)

**Interfaces:**
- Consumes: `MorningPlan.sample` (`headline`, `rightNow[0...1]`, `breakfast`, `activities[0...1]`)
- Produces: `struct PaywallPlanPreview: View { var animated: Bool = true }` — static images `"PaywallBreakfast"`, `"PaywallWalk"`, `"PaywallNap"` (breakfast, then activities in order)

Behaviour: card labelled "SAMPLE MORNING PLAN" (gold, tracked caps), serif headline, two Right-now rows, the breakfast photo with name and "around 10:30", two activity tiles. Five ticks fill in order, one every 0.55 s after a 0.4 s delay, with a light spring and no haptics. When `animated == false` or Reduce Motion is on, all five start ticked. The whole card is one accessibility element: "Sample morning plan: water and electrolytes, ibuprofen, eggs on toast with a banana, a 20-minute walk and a nap." Not interactive.

- [ ] **Step 1: Add the three imagesets** (copy the 800 px JPEGs as-is).
- [ ] **Step 2: Implement `PaywallPlanPreview`.** Use `.task` with `Task.sleep(for:)` and `withAnimation`; images `.resizable().scaledToFill()` inside fixed-height frames, `.clipped()`.
- [ ] **Step 3: Re-read for compile errors** (`@Environment(\.accessibilityReduceMotion)`, `Text` concatenation types, image names match the imageset folder names).
- [ ] **Step 4: Commit** — `git commit -m "Add the paywall hero: a sample recovery plan that ticks itself off, with real library photos"`

### Task 3: The presentational paywall screen

**Files:**
- Modify: `SipTrack/Views/Subscription/PaywallScreen.swift` (add `// MARK: - Screen`, `// MARK: - Feature strip`, `// MARK: - Plan card`)
- Modify: `SipTrack/Views/Subscription/ProView.swift` (delete `ProPlanCard`; it moves here as `PaywallPlanCard`)

**Interfaces:**
- Consumes: Task 1 copy/catalog, Task 2 `PaywallPlanPreview`
- Produces:
  - `struct PaywallPlanOption: Identifiable, Equatable { let period: SubscriptionPeriod; let price: String; let monthlyEquivalent: String?; let savings: Int?; let trial: PaywallTrial?; var id: SubscriptionPeriod { period } }`
  - `enum PaywallPlansState: Equatable { case loading, failed(String), loaded([PaywallPlanOption]) }`
  - `extension PaywallPlansState { func resolvedSelection(_ selected: SubscriptionPeriod) -> SubscriptionPeriod? }` — `selected` if loaded options contain it, else the first loaded option's period, else nil
  - `struct PaywallScreen: View { let plans: PaywallPlansState; @Binding var selected: SubscriptionPeriod; let isPurchasing: Bool; let errorMessage: String?; var animated: Bool = true; let onPurchase: () -> Void; let onRetry: () -> Void }`

Layout, top to bottom in a `ScrollView`: `PaywallPlanPreview` → `PaywallCopy.title` (`.largeTitle`, bold, `AppColors.textWarm`→`text` gradient like today's hero) → `subtitle` → `allowance` pill → feature strip → `alwaysFree` → `trust` (footnote, tertiary) → plan cards / loading / error. Bottom `safeAreaInset`: CTA (`ctaLabel` for the selected option; `ProgressView` while purchasing), `renewalTerms`, then a row of `Link`s "Terms of Use" · "Privacy Policy". When `dynamicTypeSize.isAccessibilitySize`, that bottom block goes inline at the end of the scroll content instead of being pinned. The bottom block only appears for `.loaded` with a non-empty list. `errorMessage` shows above the CTA in `AppColors.danger`.

Feature strip: chips (`icon` + `title`, capsule, surface fill, border) for `PaywallFeatures.pro`, drifting left at 28 pt/s in a seamless loop (`TimelineView(.animation)` + duplicated row, width from `onGeometryChange`). With Reduce Motion, `animated == false` or an accessibility text size: a static wrapping grid instead (`LazyVGrid` with `.adaptive(minimum: 150)`, one column at accessibility sizes). One accessibility element: "Also in Pro: " + titles joined by ", ".

Plan card (`PaywallPlanCard(option:isSelected:onTap:)`): today's `ProPlanCard` look (radio, title, BEST VALUE on yearly, price, `≈ x/mo` under yearly), subtitle = `"\(trial.adjective) free trial"` if a trial, else yearly `"Save \(savings)% vs monthly"` when savings is non-nil, else yearly "Billed once a year", monthly "Billed monthly · cancel anytime". Cards and CTA use `.disabled(isPurchasing)`. Fonts use text styles (`.headline`, `.subheadline`, `.title3`) so they scale.

- [ ] **Step 1: Add the selection test** to `PaywallTests`:

```swift
@Test func selectionFallsBackToAPlanThatLoaded() {
    let monthly = PaywallPlanOption(period: .monthly, price: "$1.99", monthlyEquivalent: nil, savings: nil, trial: nil)
    #expect(PaywallPlansState.loaded([monthly]).resolvedSelection(.yearly) == .monthly)
    #expect(PaywallPlansState.loaded([monthly]).resolvedSelection(.monthly) == .monthly)
    #expect(PaywallPlansState.loading.resolvedSelection(.yearly) == nil)
}
```

- [ ] **Step 2: Implement the three MARK sections** to the interfaces above; move `ProPlanCard`'s monthly-equivalent and BEST VALUE styling into `PaywallPlanCard`. The CTA uses the option for `plans.resolvedSelection(selected)`.
- [ ] **Step 3: Re-read for compile errors**: `@Binding` init from callers, `safeAreaInset` content builder with `if`, `onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action:)`, `Link` destinations force-unwrapped like today.
- [ ] **Step 4: Commit** — `git commit -m "Build the presentational paywall screen: hero, drifting feature chips, plan cards and a pinned price bar"`

### Task 4: Wire `ProView` to the new screen

**Files:**
- Modify: `SipTrack/Views/Subscription/ProView.swift`

**Interfaces:**
- Consumes: `PaywallScreen`, `PaywallPlanOption`, `PaywallPlansState`, `PaywallTrial(offer:)`, `PaywallCopy.savingsPercent`, `PaywallFeatures.membership`; `StoreManager.product(for:)`, `isLoadingProducts`, `products`, `loadError`, `retryLoadProducts()`, `restorePurchases()`, `restoreError` (all unchanged)
- Produces: nothing new; `ProView(presentation:)` keeps its signature.

Changes:
- Free user: `content` renders `PaywallScreen` (inside the existing `NavigationStack` for `.modal`), replacing `hero`, `upgradeBody`, `beerValueCallout`, `proFeaturesGrid`, `pricingBlock`, `inlineCTA`, `legalAndRestore`, `stickyFooter`, `stickyPlanLabel`, `purchaseLabel`, `ScrollOffsetKey` and the scroll tracking. Navigation title "Tracksip Pro", inline.
- Toolbar: `.modal` keeps the leading X; both presentations get a trailing "Restore" button running today's restore closure (`await store.restorePurchases(); errorMessage = store.restoreError; appState.syncSubscriptionFromStore()`), disabled while purchasing.
- `plans`: `.loading` while `store.isLoadingProducts`; `.failed(store.loadError ?? "Could not load plans")` when products are empty; else `.loaded` built from `[.yearly, .monthly]` via `store.product(for:)`, skipping missing ones; yearly `monthlyEquivalent` = `product.priceFormatStyle.format(product.price / 12)` with "≈ …/mo"; `savings` from both prices when both exist.
- Trials: `@State private var trials: [SubscriptionPeriod: PaywallTrial] = [:]`, filled in `.task(id: store.products.map(\.id))`: for each of yearly/monthly, if `await product.subscription?.isEligibleForIntroOffer == true`, map `product.subscription?.introductoryOffer` through `PaywallTrial(offer:)`.
- `selectedPeriod`: after products change, set it to `plans.resolvedSelection(selectedPeriod)` when non-nil (`.onChange(of: store.products)`), and `purchase()` reads the product for that period.
- Pro member: keep `proActiveBody` and hero as today but build `proInventoryCard` from `PaywallFeatures.membership`.
- `purchase()` unchanged.

- [ ] **Step 1: Make the changes above.**
- [ ] **Step 2: Grep for leftovers**: `grep -n "ScrollOffsetKey\|ProPlanCard\|beerValueCallout\|stickyFooter" SipTrack -r` → no matches.
- [ ] **Step 3: Re-read `ProView.swift` top to bottom for compile errors** (unused `@State` removed, `heroBreath` still used by the member hero, `Product` arithmetic on `Decimal`).
- [ ] **Step 4: Commit** — `git commit -m "Show the new paywall to free users and keep purchase, restore and the member view as they were"`

### Task 5: Screenshots from CI

**Files:**
- Modify: `siptrackTests/PaywallTests.swift` (add `PaywallRenderTests`)
- Modify: `.github/workflows/ci.yml` (upload step)

**Interfaces:**
- Consumes: `PaywallScreen(plans:selected:isPurchasing:errorMessage:animated:onPurchase:onRetry:)`

The test renders `NavigationStack { PaywallScreen(…, animated: false) }` with two loaded options (yearly "$19.99", "≈ $1.67/mo", savings 16; monthly "$1.99") in a `UIWindow` via `UIHostingController`, at 375×667 and 440×956, each at `.large` and `.accessibility5` (`.environment(\.dynamicTypeSize, …)`), plus 375×667 `.loading` and `.failed("Plans are unavailable right now. Please try again later.")`. It draws with `drawHierarchy(in:afterScreenUpdates: true)`, asserts each image is non-empty, and writes `paywall-<w>x<h>-<size>.png` to `<repo>/build/paywall-shots/` (repo root from `#filePath`).

- [ ] **Step 1: Add `PaywallRenderTests`** (`@MainActor`, `@Test func rendersAtSmallAndLargeSizes() throws`).
- [ ] **Step 2: Add to `ci.yml`** after "Test": `- name: Upload paywall screenshots` / `if: always()` / `uses: actions/upload-artifact@v4` / `with: name: paywall-shots, path: build/paywall-shots, if-no-files-found: ignore, retention-days: 7`.
- [ ] **Step 3: Commit** — `git commit -m "Render the paywall at small and large iPhone sizes and text sizes in CI and upload the screenshots"`

### Task 6: Ship

- [ ] **Step 1:** Push `feat/paywall-redesign`, open a PR into `dev`, bind it with the PR tools and read CI there. Expected: "Build & test (iOS Simulator)" and "Backend and security rules" pass.
- [ ] **Step 2:** `gh run download <run-id> -n paywall-shots`; look at all six PNGs. Fix truncation/overlap, push, repeat.
- [ ] **Step 3:** Show the screenshots to the owner; on their OK merge into `dev` (their merge or explicit go-ahead), then open `dev`→`main`. Merge to main only with the owner's explicit OK. Watch the TestFlight workflow; if "Archive & upload" is cancelled with "not acquired by Runner", `gh run rerun <id> --failed`. Tell the owner when the build is in TestFlight.
