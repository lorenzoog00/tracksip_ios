# SipTrack iOS — Native Swift Rewrite

Full SwiftUI rewrite of the SipTrack Expo app. iOS-only, StoreKit 2, App Group storage for future Watch extension.

## Xcode Project Setup

1. **Create project in Xcode**
   - File → New → Project → iOS → App
   - Product Name: `SipTrack`
   - Bundle Identifier: `com.siptrack.app` (must match App Store Connect)
   - Interface: SwiftUI
   - Minimum Deployment: iOS 16.0

2. **Add all Swift files**
   - Drag the `SipTrack/` folder from this repo into the Xcode project
   - Ensure "Copy items if needed" is unchecked (files are already in the project directory)

3. **Configure App Group** (required for Watch sharing later)
   - Target → Signing & Capabilities → + Capability → App Groups
   - Add group: `group.com.siptrack.shared`

4. **Configure StoreKit**
   - In App Store Connect, create 3 In-App Purchase products:
     - `com.siptrack.pro.monthly`  — Auto-Renewable Subscription, $1.99/mo
     - `com.siptrack.pro.yearly`   — Auto-Renewable Subscription, $19.99/yr
     - `com.siptrack.pro.lifetime` — Non-Consumable, $59.99
   - For local testing: File → New → File → StoreKit Configuration
     - Add matching products with those identifiers
     - Edit Scheme → Run → Options → StoreKit Configuration → select file

5. **Supabase (optional — for cloud sync)**
   - Add `supabase-swift` via Swift Package Manager
   - Create `Config.swift` with your project URL and anon key

## Architecture

```
SipTrack/
├── SipTrackApp.swift          Entry point, injects store + appState
├── Constants/
│   └── AppColors.swift        Dark theme color palette
├── Models/
│   ├── DrinkType.swift        DrinkType + 16 presets
│   ├── NightEvent.swift       NightEvent, DrinkEntry, WaterEntry
│   ├── UserProfile.swift      UserProfile, Sex, SubscriptionTier
│   └── Challenge.swift        Challenge, ChallengeType
├── Core/
│   ├── BACCalculator.swift    Widmark + Watson formulas, hydration
│   ├── IntoxicationStage.swift 7 intoxication stages with colors
│   ├── WarningSystem.swift    Drink warning builder
│   ├── Analytics.swift        AllTimeStats, MonthlyStats computation
│   └── ChallengeUtils.swift   Challenge progress computation
├── Storage/
│   └── AppStorage.swift       JSON file persistence via App Group container
├── Store/
│   └── StoreManager.swift     StoreKit 2 — products, purchase, restore
├── State/
│   └── AppState.swift         Central @MainActor ObservableObject
├── Navigation/
│   └── Route.swift            NavigationStack route enum
└── Views/
    ├── RootView.swift          Root nav stack + onboarding gate
    ├── Onboarding/
    │   ├── OnboardingView.swift
    │   └── DisclaimerView.swift
    ├── Home/HomeView.swift
    ├── Event/
    │   ├── CreateEventView.swift
    │   └── ActiveEventView.swift
    ├── Summary/SummaryView.swift
    ├── Calendar/CalendarView.swift
    ├── Dashboard/DashboardView.swift
    ├── Challenges/ChallengesView.swift
    ├── Drinks/
    │   ├── DrinksView.swift
    │   └── EditDrinkView.swift
    ├── Entry/EditEntryView.swift
    ├── Profile/ProfileView.swift
    └── Subscription/
        ├── SubscriptionView.swift
        └── PaywallView.swift
```

## Key Differences from Expo Version

| Expo                     | Swift                              |
|--------------------------|------------------------------------|
| RevenueCat               | StoreKit 2 native                  |
| AsyncStorage             | JSON files in App Group container  |
| NocheContext (React)     | AppState @MainActor ObservableObject |
| Expo Router              | NavigationStack + Route enum       |
| Ionicons                 | SF Symbols                         |
| Median bridge            | Native iOS — no bridge needed      |
| Google Mobile Ads        | Remove or add GoogleMobileAds SDK  |

## Next Steps

- [ ] Add watchOS target with shared App Group reads
- [ ] Add Supabase sync (supabase-swift package) for multi-device
- [ ] Add push notifications (UNUserNotificationCenter)
- [ ] Add share sheet for event summary
- [ ] Add haptic feedback (UIImpactFeedbackGenerator)
- [ ] App icon + launch screen
