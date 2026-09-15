# SipTrack iOS

Native SwiftUI app for tracking blood alcohol content across a night out — live BAC estimation, drink logging, history, AI-generated night/coach reports, and a watchOS companion.

Open `siptrack.xcodeproj` in Xcode. There is no CocoaPods/Carthage step; all dependencies resolve through Swift Package Manager.

## Targets

| Target | Bundle ID | Platform |
|--------|-----------|----------|
| SipTrack | `com.lorenzoog.siptrack` | iOS 18.0 |
| SipTrackWidgets | `com.lorenzoog.siptrack.SipTrackWidgets` | iOS 18.0 |
| SipTrack Watch Watch App | `com.lorenzoog.siptrack.watchkitapp` | watchOS 26.4 |
| siptrackTests / siptrackUITests | `com.lorenzoog.siptrack{Tests,UITests}` | iOS 18.0 |

Swift 5.0. App Group `group.lorenzoog.siptrack` backs storage shared between the app, widgets, and Watch.

## Dependencies

Remote (SPM): `firebase-ios-sdk`, `GoogleSignIn-iOS`, `swift-package-manager-google-mobile-ads`.
Local (SPM): `SipTrackActivityKit/` — Live Activity attributes shared by the app and the widget extension.

## Configuration

**Firebase** — `GoogleService-Info.plist` at the repo root. Firestore, Auth (Google + Apple Sign-In), and Crashlytics. Rules in `firestore.rules`, project config in `firebase.json`.

**StoreKit** — three products, defined in App Store Connect and mirrored in `Siptrack.storekit` for local testing:

- `com.lorenzoog.siptrack.pro.monthly` — auto-renewable subscription
- `com.lorenzoog.siptrack.pro.yearly` — auto-renewable subscription
- `com.lorenzoog.siptrack.pro.lifetime` — non-consumable

To test purchases locally: Edit Scheme → Run → Options → StoreKit Configuration → `Siptrack.storekit`.

**Cloud Functions** ? `functions/` (Node 24). Authenticated, App Check protected `requestReport` and `deleteAccount` callables replace direct Firestore report triggers. See [release steps](docs/RELEASE.md) for Apple purchase verification, secrets, deployment, and test commands.

## Layout

```
SipTrack/
├── SipTrackApp.swift       Entry point, injects StoreManager + AppState
├── Core/                   BAC engine, intoxication stages, warnings, analytics
├── Models/                 DrinkType, NightEvent, UserProfile, Challenge
├── State/AppState.swift    Central @MainActor ObservableObject
├── Storage/AppStorage.swift JSON persistence in the App Group container
├── Store/StoreManager.swift StoreKit 2 — products, purchase, restore
├── Ads/                    Google Mobile Ads banner/native + consent
├── Navigation/Route.swift  NavigationStack route enum
└── Views/                  Home, Event, Summary, Calendar, Dashboard,
                            Challenges, Coach, Drinks, Entry, Onboarding,
                            Profile, Subscription
Firebase/                   FirebaseManager — auth, Firestore sync
SipTrackWidgets/            Widget bundle + Live Activity UI
SipTrackActivityKit/        Shared Live Activity attributes (SPM, iOS 16+)
SipTrack Watch Watch App/   watchOS companion
functions/                  Firebase Cloud Functions (Node)
```

Persistence is local-first: `DataStore` writes JSON to the App Group container, and Firebase syncs on top. There is no Core Data or SwiftData.

## BAC model

`SipTrack/Core/BACCalculator.swift` forward-integrates a one-compartment model in one-minute steps:

- Widmark volume of distribution, individualized via Watson/Forrest body-water equations
- Sex-specific first-pass metabolism
- Per-drink first-order gut absorption, with `kA` calibrated against published Tmax/Cmax by ABV and slowed by food/stomach state
- Michaelis-Menten elimination (not zero-order), calibrated so the rate matches published β at a 0.08 reference

Drinks consumed fast enough to trip gulp detection switch to instant Widmark absorption. That is a deliberate UX choice over strict pharmacokinetic accuracy — see the note at the top of `BACCalculator.swift`.

## Tests

`siptrackTests/` covers the BAC math and report logic: `BACCalculatorCoreTests`, `BACCalculatorKineticsTests`, `BACCalculatorFoodTests`, `DrinkServingSizeTests`, `AIInsightsTests`, `NightPickerTests`. Run with Cmd-U.

Views, `AppState`, Firebase sync, `StoreManager`, ads, and the Watch/widget targets are not currently covered.

## Docs

- `product.md` — product spec
- `docs/COMPANION-ROADMAP.md` — agreed next steps for the companion/safety features
