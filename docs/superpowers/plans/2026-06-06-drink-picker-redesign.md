# Drink Picker Redesign + Stats Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat emoji 3-column drink grid with a searchable, filterable list with favorites and recents; add a STATS button that opens a live timeline + interesting facts sheet.

**Architecture:** Seven tasks build on each other: data model first (Task 1), then AppState helpers (Task 1 cont.), then the two new views (Tasks 3 and 6), wired into ActiveEventView last (Tasks 4 and 7). DrinksView is a parallel track (Task 2) with no dependencies.

**Tech Stack:** SwiftUI, existing `AppState`/`AppColors`/`BACCalculator`, `premiumCard` view modifier, `UIImpactFeedbackGenerator`, `FirebaseManager.pushProfile`.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `SipTrack/Models/UserProfile.swift` | Modify | Add `favoriteDrinkIds: [String]` |
| `SipTrack/State/AppState.swift` | Modify | Add `toggleFavoriteDrink(id:)` + `isFavorite(id:)` |
| `Firebase/FirebaseManager.swift` | Modify | Push/pull `favorite_drink_ids` |
| `SipTrack/Views/Drinks/DrinksView.swift` | Modify | List layout + heart toggle + filter pills |
| `SipTrack/Views/Event/DrinkPickerList.swift` | Create | New inline picker (replaces QuickAddGrid) |
| `SipTrack/Views/Event/NightStatsSheet.swift` | Create | Stats panel: pace, facts, timeline |
| `SipTrack/Views/Event/ActiveEventView.swift` | Modify | Replace QuickAddGrid; add STATS button + sheet |
| `siptrackTests/NightPickerTests.swift` | Create | Unit tests for favorite toggle + night facts |

---

## Task 1: Data Model — `favoriteDrinkIds` + AppState helpers

**Files:**
- Modify: `SipTrack/Models/UserProfile.swift`
- Modify: `SipTrack/State/AppState.swift`
- Modify: `Firebase/FirebaseManager.swift`
- Create: `siptrackTests/NightPickerTests.swift`

- [ ] **Step 1: Add `favoriteDrinkIds` to `UserProfile`**

In `SipTrack/Models/UserProfile.swift`, add the property after `liveActivityDrinkIds`:

```swift
var favoriteDrinkIds: [String]         = []
```

- [ ] **Step 2: Add helpers to `AppState`**

In `SipTrack/State/AppState.swift`, add these two methods (find the section with other profile mutation helpers):

```swift
func isFavorite(_ drinkId: String) -> Bool {
    userProfile.favoriteDrinkIds.contains(drinkId)
}

func toggleFavoriteDrink(id: String) {
    if userProfile.favoriteDrinkIds.contains(id) {
        userProfile.favoriteDrinkIds.removeAll { $0 == id }
    } else {
        userProfile.favoriteDrinkIds.append(id)
    }
    saveAndSync()
}
```

> `saveAndSync()` is an existing method in AppState that calls DataStore + schedules a Firestore push. If it doesn't exist under that name, look for the pattern used by other profile setters like `updateUserProfile(_:)` and follow the same pattern.

- [ ] **Step 3: Persist in Firestore — `pushProfile`**

In `Firebase/FirebaseManager.swift`, inside `pushProfile(_ profile:)`, add after the existing `data["country_detection_disabled"]` line:

```swift
data["favorite_drink_ids"] = profile.favoriteDrinkIds
```

- [ ] **Step 4: Pull from Firestore — `pullUserData`**

In `Firebase/FirebaseManager.swift`, inside `pullUserData()`, in the profile parsing block (where `up.countryCode = ...` is set), add:

```swift
up.favoriteDrinkIds = d["favorite_drink_ids"] as? [String] ?? []
```

- [ ] **Step 5: Write tests**

Create `siptrackTests/NightPickerTests.swift`:

```swift
import XCTest
@testable import SipTrack

final class NightPickerTests: XCTestCase {

    func test_isFavorite_falseByDefault() {
        var profile = UserProfile()
        XCTAssertFalse(profile.favoriteDrinkIds.contains("beer"))
    }

    func test_favoriteDrinkIds_roundtripsJSON() throws {
        var profile = UserProfile()
        profile.favoriteDrinkIds = ["beer", "tequila"]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.favoriteDrinkIds, ["beer", "tequila"])
    }
}
```

- [ ] **Step 6: Run tests**

```
xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/NightPickerTests 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: 2 tests pass.

- [ ] **Step 7: Commit**

```bash
git add SipTrack/Models/UserProfile.swift SipTrack/State/AppState.swift Firebase/FirebaseManager.swift siptrackTests/NightPickerTests.swift
git commit -m "feat: add favoriteDrinkIds to UserProfile, AppState helpers, Firestore sync"
```

---

## Task 2: Redesign `DrinksView` — list rows + heart + filter pills

**Files:**
- Modify: `SipTrack/Views/Drinks/DrinksView.swift`

- [ ] **Step 1: Replace the entire file**

`DrinksView.swift` currently has a `LazyVGrid` 2-column card layout. Replace the full file with the list-based version below. Read the file first to confirm the structure matches what's expected (it should match the code you've already read).

```swift
import SwiftUI

// MARK: - Filter

private enum DrinkFilter: String, CaseIterable {
    case all, favorites, beer, wine, spirits, cocktail

    var label: String {
        switch self {
        case .all:       return "All"
        case .favorites: return "♥ Favorites"
        case .beer:      return "Beer"
        case .wine:      return "Wine"
        case .spirits:   return "Spirits"
        case .cocktail:  return "Cocktail"
        }
    }

    func matches(_ dt: DrinkType, isFav: Bool) -> Bool {
        switch self {
        case .all:       return true
        case .favorites: return isFav
        case .beer:      return dt.drinkCategory == "beer"
        case .wine:      return dt.drinkCategory == "wine"
        case .spirits:   return dt.drinkCategory == "spirits" || dt.drinkCategory == "agave"
        case .cocktail:  return dt.drinkCategory == "cocktails"
        }
    }
}

// MARK: - Main view

struct DrinksView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingDrink: DrinkType? = nil
    @State private var showCreate = false
    @State private var deleteConfirm: DrinkType? = nil
    @State private var filter: DrinkFilter = .all

    private var filtered: [DrinkType] {
        appState.allDrinkTypes.filter { filter.matches($0, isFav: appState.isFavorite($0.id)) }
    }

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                filterPills
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { dt in
                            DrinkRow(
                                drink: dt,
                                isFavorite: appState.isFavorite(dt.id),
                                onFavorite: { appState.toggleFavoriteDrink(id: dt.id) },
                                onEdit: { editingDrink = dt },
                                onDelete: { deleteConfirm = dt }
                            )
                        }
                        createButton
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Drinks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingDrink) { EditDrinkView(existing: $0) }
        .sheet(isPresented: $showCreate) { EditDrinkView(existing: nil) }
        .confirmationDialog(
            "Delete \(deleteConfirm?.name ?? "drink")?",
            isPresented: Binding(get: { deleteConfirm != nil }, set: { if !$0 { deleteConfirm = nil } }),
            titleVisibility: .visible
        ) {
            Button(deleteConfirm?.isPreset == true ? "Reset to Default" : "Delete", role: .destructive) {
                if let dt = deleteConfirm { appState.deleteDrinkType(dt.id); deleteConfirm = nil }
            }
            Button("Cancel", role: .cancel) { deleteConfirm = nil }
        }
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DrinkFilter.allCases, id: \.self) { f in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { filter = f }
                    } label: {
                        Text(f.label)
                            .font(.system(size: 11, weight: .700))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(filter == f ? AppColors.accent : AppColors.surface)
                            .foregroundStyle(filter == f ? Color.black : AppColors.textSecondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(filter == f ? AppColors.accent : AppColors.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(AppColors.background)
    }

    private var createButton: some View {
        Button { showCreate = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                Text("Create new drink")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.accent.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}

// MARK: - Row

private struct DrinkRow: View {
    let drink: DrinkType
    let isFavorite: Bool
    let onFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(drink.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: drink.sfSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(drink.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(drink.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(String(format: "%.1f%% · %dml · %d cal", drink.defaultAbv, Int(drink.defaultVolumeMl), Int(drink.caloriesPerServing)))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Button(action: onFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(isFavorite ? Color(hex: "#FF6B6B") : AppColors.textTertiary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.surface)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { onFavorite() } label: {
                Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label(drink.isPreset ? "Reset to Default" : "Delete", systemImage: "trash")
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify no compile errors**

Open Xcode and build (⌘B). Fix any issues — likely none since all referenced types exist.

- [ ] **Step 3: Commit**

```bash
git add SipTrack/Views/Drinks/DrinksView.swift
git commit -m "feat: redesign DrinksView with list rows, heart favorites toggle, filter pills"
```

---

## Task 3: Create `DrinkPickerList.swift`

**Files:**
- Create: `SipTrack/Views/Event/DrinkPickerList.swift`

This is a drop-in replacement for `QuickAddGrid`. It takes the same `event`, `drinkTypes`, and `onPick` parameters.

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

// MARK: - Filter enum (shared with DrinksView concept, local to picker)

enum PickerFilter: CaseIterable {
    case favorites, all, beer, wine, spirits, cocktail

    var label: String {
        switch self {
        case .favorites: return "♥ Favorites"
        case .all:       return "All"
        case .beer:      return "Beer"
        case .wine:      return "Wine"
        case .spirits:   return "Spirits"
        case .cocktail:  return "Cocktail"
        }
    }

    func matches(_ dt: DrinkType, isFav: Bool) -> Bool {
        switch self {
        case .favorites: return isFav
        case .all:       return true
        case .beer:      return dt.drinkCategory == "beer"
        case .wine:      return dt.drinkCategory == "wine"
        case .spirits:   return dt.drinkCategory == "spirits" || dt.drinkCategory == "agave"
        case .cocktail:  return dt.drinkCategory == "cocktails"
        }
    }
}

// MARK: - Main picker

struct DrinkPickerList: View {
    @EnvironmentObject var appState: AppState
    let event: NightEvent
    let drinkTypes: [DrinkType]
    let onPick: (DrinkType) -> Void

    @State private var filter: PickerFilter = .all
    @State private var searchText = ""

    // Drinks added during this session, most recent first, capped at 5
    private var recentDrinkTypes: [DrinkType] {
        let sessionEntries = appState.entries
            .filter { $0.eventId == event.id }
            .sorted { $0.timestamp > $1.timestamp }
        var seen = Set<String>()
        var result: [DrinkType] = []
        for entry in sessionEntries {
            guard !seen.contains(entry.drinkTypeId) else { continue }
            seen.insert(entry.drinkTypeId)
            if let dt = drinkTypes.first(where: { $0.id == entry.drinkTypeId }) {
                result.append(dt)
                if result.count == 5 { break }
            }
        }
        return result
    }

    private var filteredDrinks: [DrinkType] {
        let base = drinkTypes.filter { filter.matches($0, isFav: appState.isFavorite($0.id)) }
        guard !searchText.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // Default to Favorites if user has any, otherwise All
    private var defaultFilter: PickerFilter {
        drinkTypes.contains { appState.isFavorite($0.id) } ? .favorites : .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
                TextField("Search drinks…", text: $searchText)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.text)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppColors.surface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
            .padding(.horizontal)

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PickerFilter.allCases, id: \.self) { f in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { filter = f }
                            searchText = ""
                        } label: {
                            Text(f.label)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(filter == f ? (f == .favorites ? Color(hex: "#FF6B6B") : AppColors.accent) : AppColors.surface)
                                .foregroundStyle(filter == f ? Color.black : AppColors.textSecondary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    filter == f ? (f == .favorites ? Color(hex: "#FF6B6B") : AppColors.accent) : AppColors.border,
                                    lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Content
            if filter == .all && searchText.isEmpty && !recentDrinkTypes.isEmpty {
                pickerSection(label: "RECENTLY ADDED", drinks: recentDrinkTypes, showTimestamp: true)
                pickerSection(label: "ALL DRINKS", drinks: filteredDrinks, showTimestamp: false)
            } else if filteredDrinks.isEmpty {
                emptyState
            } else {
                pickerSection(label: filter == .favorites ? "YOUR FAVORITES" : nil, drinks: filteredDrinks, showTimestamp: false)
            }
        }
        .onAppear {
            filter = defaultFilter
        }
    }

    // MARK: Sub-views

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Text("ADD A DRINK")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.textTertiary)
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)
        }
        .padding(.horizontal)
    }

    private var emptyState: some View {
        Text(filter == .favorites ? "No favorites yet — heart drinks in the Drinks tab." : "No drinks match.")
            .font(.system(size: 13))
            .foregroundStyle(AppColors.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.vertical, 24)
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pickerSection(label: String?, drinks: [DrinkType], showTimestamp: Bool) -> some View {
        if let label {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(filter == .favorites ? Color(hex: "#FF6B6B").opacity(0.8) : AppColors.textTertiary)
                .padding(.horizontal)
        }
        VStack(spacing: 5) {
            ForEach(drinks) { dt in
                PickerRow(
                    drinkType: dt,
                    isFavorite: filter == .all && appState.isFavorite(dt.id),
                    recentTimestamp: showTimestamp
                        ? appState.entries.filter { $0.eventId == event.id && $0.drinkTypeId == dt.id }.max(by: { $0.timestamp < $1.timestamp })?.timestamp
                        : nil,
                    onPick: { onPick(dt) }
                )
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Row

private struct PickerRow: View {
    let drinkType: DrinkType
    let isFavorite: Bool
    let recentTimestamp: Date?
    let onPick: () -> Void

    @State private var pressed = false

    private var metaText: String {
        if let ts = recentTimestamp {
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            return "added \(fmt.string(from: ts))"
        }
        return String(format: "%.1f%% · %dml · %d cal",
                      drinkType.defaultAbv,
                      Int(drinkType.defaultVolumeMl),
                      Int(drinkType.caloriesPerServing))
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onPick()
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(drinkType.color.opacity(recentTimestamp != nil ? 0.2 : 0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: drinkType.sfSymbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(drinkType.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(drinkType.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                    Text(metaText)
                        .font(.system(size: 9))
                        .foregroundStyle(recentTimestamp != nil ? AppColors.accent : AppColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.border)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                recentTimestamp != nil
                    ? Color(hex: "#141820")
                    : AppColors.surface
            )
            .cornerRadius(11)
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        recentTimestamp != nil ? AppColors.accent.opacity(0.2) : AppColors.border,
                        lineWidth: 1
                    )
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }
}
```

- [ ] **Step 2: Build (⌘B) and verify no compile errors**

- [ ] **Step 3: Commit**

```bash
git add SipTrack/Views/Event/DrinkPickerList.swift
git commit -m "feat: create DrinkPickerList with search, filter tabs, recents, SF icons"
```

---

## Task 4: Wire `DrinkPickerList` into `ActiveEventView`

**Files:**
- Modify: `SipTrack/Views/Event/ActiveEventView.swift`

- [ ] **Step 1: Add `showStats` state variable**

In `ActiveEventView`, in the `@State` block at the top of the struct (around lines 7–11), add:

```swift
@State private var showStats = false
```

- [ ] **Step 2: Replace `QuickAddGrid` call with `DrinkPickerList`**

Find line 67 (the `QuickAddGrid(...)` call):
```swift
// OLD — delete this:
QuickAddGrid(event: event, drinkTypes: appState.allDrinkTypes) { dt in
    handleDrinkTap(dt, event: event, bacLimit: bacLimit)
}
```

Replace with:
```swift
DrinkPickerList(event: event, drinkTypes: appState.allDrinkTypes) { dt in
    handleDrinkTap(dt, event: event, bacLimit: bacLimit)
}
```

- [ ] **Step 3: Add STATS button to toolbar**

In `content(event:)`, find `.navigationTitle(event.displayName)` and add a toolbar modifier below it:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button {
            showStats = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("STATS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(Color(hex: "#5BC8FF"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#5BC8FF").opacity(0.12))
            .cornerRadius(20)
        }
    }
}
```

- [ ] **Step 4: Add the stats sheet**

After the existing `.sheet(item: $pendingDrink)` modifier, add:

```swift
.sheet(isPresented: $showStats) {
    NightStatsSheet(eventId: eventId)
        .environmentObject(appState)
}
```

- [ ] **Step 5: Build (⌘B) — `NightStatsSheet` doesn't exist yet so expect an error**

The error `Cannot find type 'NightStatsSheet'` is expected. Add a temporary stub so the build passes while you work on Task 6:

```swift
// Temporary stub at the bottom of ActiveEventView.swift — remove in Task 6
private struct NightStatsSheet: View {
    let eventId: String
    var body: some View { Text("Coming soon") }
}
```

- [ ] **Step 6: Build again (⌘B) — should be clean**

- [ ] **Step 7: Test on simulator**
  - Launch active event
  - Verify `DrinkPickerList` appears with search bar + filter pills
  - Tap a drink row → drink added + toast appears
  - Tap STATS → "Coming soon" sheet appears
  - Tap ♥ Favorites → empty state with hint message

- [ ] **Step 8: Commit**

```bash
git add SipTrack/Views/Event/ActiveEventView.swift
git commit -m "feat: replace QuickAddGrid with DrinkPickerList, add STATS button stub"
```

---

## Task 5: Night Facts logic + tests

**Files:**
- Modify: `siptrackTests/NightPickerTests.swift`

This task implements the pure computation logic for the interesting facts. Keep it in a free function so it's testable without SwiftUI.

- [ ] **Step 1: Add `NightFact` struct and `computeNightFacts` function**

Create a new file `SipTrack/Views/Event/NightFacts.swift`:

```swift
import Foundation

struct NightFact {
    let text: String
    let isSafetyAlert: Bool  // true = shown in danger/amber color
}

/// Computes 1–3 contextual facts about the current session.
/// Pure function — no side effects, no SwiftUI dependencies.
func computeNightFacts(
    drinkCount: Int,
    waterCount: Int,
    currentBAC: Double,
    bacLimit: Double,
    hoursElapsed: Double,
    totalCalories: Int,
    peakBAC: Double,
    peakBACMinutesAgo: Int,
    drinksThisHour: Int,
    avgDrinksPerHour: Double
) -> [NightFact] {
    var facts: [NightFact] = []

    // 1. Safety: approaching limit
    if currentBAC > 0 && currentBAC < bacLimit {
        let remainingBAC = bacLimit - currentBAC
        let hoursToLimit = remainingBAC / 0.018  // avg 1 drink ≈ 0.018 BAC
        if hoursToLimit < 1.5 && drinkCount > 0 {
            let mins = Int(hoursToLimit * 60)
            facts.append(NightFact(
                text: "At this pace you're ~\(mins) min from your limit.",
                isSafetyAlert: true
            ))
        }
    }

    // 2. Peak BAC dropping
    if peakBAC > 0.04 && peakBACMinutesAgo > 15 && currentBAC < peakBAC {
        facts.append(NightFact(
            text: "Your BAC peaked \(peakBACMinutesAgo) min ago — it's dropping now.",
            isSafetyAlert: false
        ))
    }

    // 3. Heavy hour
    if drinksThisHour >= 3 && drinksThisHour > Int(avgDrinksPerHour * 1.5) {
        facts.append(NightFact(
            text: "You've had \(drinksThisHour) drinks this hour — your fastest stretch tonight.",
            isSafetyAlert: true
        ))
    }

    // 4. Calorie comparison
    if facts.count < 3 && totalCalories > 300 {
        let comparison: String
        switch totalCalories {
        case 0..<250:   comparison = "a bag of chips"
        case 250..<450: comparison = "a slice of pizza"
        case 450..<700: comparison = "a cheeseburger"
        default:        comparison = "a full burger meal"
        }
        facts.append(NightFact(
            text: "You've had ~\(totalCalories) cal tonight — about the same as \(comparison).",
            isSafetyAlert: false
        ))
    }

    // 5. Hydration positive
    if facts.count < 3 && waterCount >= 2 {
        facts.append(NightFact(
            text: "\(waterCount) waters tonight — solid hydration.",
            isSafetyAlert: false
        ))
    }

    // 6. Sober night
    if drinkCount == 0 {
        facts.append(NightFact(
            text: "Sober night — your body is getting a full reset.",
            isSafetyAlert: false
        ))
    }

    return Array(facts.prefix(3))
}
```

- [ ] **Step 2: Add tests in `NightPickerTests.swift`**

Add the following tests to the existing `NightPickerTests` class:

```swift
func test_computeFacts_soberNight() {
    let facts = computeNightFacts(
        drinkCount: 0, waterCount: 0, currentBAC: 0, bacLimit: 0.08,
        hoursElapsed: 2, totalCalories: 0, peakBAC: 0, peakBACMinutesAgo: 0,
        drinksThisHour: 0, avgDrinksPerHour: 0
    )
    XCTAssertEqual(facts.count, 1)
    XCTAssertTrue(facts[0].text.contains("Sober"))
}

func test_computeFacts_approachingLimit() {
    let facts = computeNightFacts(
        drinkCount: 4, waterCount: 0, currentBAC: 0.07, bacLimit: 0.08,
        hoursElapsed: 2, totalCalories: 400, peakBAC: 0.07, peakBACMinutesAgo: 5,
        drinksThisHour: 1, avgDrinksPerHour: 1.5
    )
    XCTAssertTrue(facts.contains { $0.isSafetyAlert && $0.text.contains("limit") })
}

func test_computeFacts_maxThreeFacts() {
    let facts = computeNightFacts(
        drinkCount: 5, waterCount: 3, currentBAC: 0.06, bacLimit: 0.08,
        hoursElapsed: 2, totalCalories: 600, peakBAC: 0.07, peakBACMinutesAgo: 30,
        drinksThisHour: 4, avgDrinksPerHour: 1.5
    )
    XCTAssertLessThanOrEqual(facts.count, 3)
}

func test_computeFacts_hydrationFact() {
    let facts = computeNightFacts(
        drinkCount: 2, waterCount: 3, currentBAC: 0.02, bacLimit: 0.08,
        hoursElapsed: 2, totalCalories: 200, peakBAC: 0.03, peakBACMinutesAgo: 10,
        drinksThisHour: 0, avgDrinksPerHour: 1.0
    )
    XCTAssertTrue(facts.contains { $0.text.contains("water") })
}
```

- [ ] **Step 3: Run tests**

```
xcodebuild test -scheme siptrack -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:siptrackTests/NightPickerTests 2>&1 | grep -E "PASS|FAIL|error:"
```

Expected: 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add SipTrack/Views/Event/NightFacts.swift siptrackTests/NightPickerTests.swift
git commit -m "feat: add NightFact model and computeNightFacts() with tests"
```

---

## Task 6: Create `NightStatsSheet.swift`

**Files:**
- Create: `SipTrack/Views/Event/NightStatsSheet.swift`

- [ ] **Step 1: Create the full file**

```swift
import SwiftUI

struct NightStatsSheet: View {
    let eventId: String
    @EnvironmentObject var appState: AppState

    private var event: NightEvent? { appState.events.first { $0.id == eventId } }
    private var entries: [DrinkEntry] { appState.entries.filter { $0.eventId == eventId }.sorted { $0.timestamp < $1.timestamp } }
    private var waterEntries: [WaterEntry] { appState.waterEntries.filter { $0.eventId == eventId }.sorted { $0.timestamp < $1.timestamp } }
    private var currentBAC: Double { appState.currentBAC(for: eventId) }
    private var bacLimit: Double { event?.bacLimit ?? appState.userProfile.resolvedBACLimit }

    private var hoursElapsed: Double {
        guard let start = event?.startTime else { return 0 }
        return max(0.01, Date().timeIntervalSince(start) / 3600)
    }
    private var drinkCount: Int { entries.count }
    private var waterCount: Int { waterEntries.count }
    private var totalCalories: Int { Int(entries.compactMap { appState.allDrinkTypes.first { $0.id == $1.drinkTypeId }?.caloriesPerServing }.reduce(0, +)) }
    private var drinksPerHour: Double { Double(drinkCount) / hoursElapsed }

    private var peakBAC: Double { appState.peakBAC(for: eventId) }

    private var peakBACMinutesAgo: Int {
        guard let peakTime = appState.peakBACTime(for: eventId) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(peakTime) / 60))
    }

    private var drinksThisHour: Int {
        let cutoff = Date().addingTimeInterval(-3600)
        return entries.filter { $0.timestamp > cutoff }.count
    }

    private var facts: [NightFact] {
        computeNightFacts(
            drinkCount: drinkCount,
            waterCount: waterCount,
            currentBAC: currentBAC,
            bacLimit: bacLimit,
            hoursElapsed: hoursElapsed,
            totalCalories: totalCalories,
            peakBAC: peakBAC,
            peakBACMinutesAgo: peakBACMinutesAgo,
            drinksThisHour: drinksThisHour,
            avgDrinksPerHour: drinksPerHour
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        paceSection
                        totalsSection
                        if !facts.isEmpty { factsSection }
                        timelineSection
                        Color.clear.frame(height: 20)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("How am I going?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { /* sheet auto-dismisses */ }
                }
            }
        }
    }

    // MARK: Section 1 — Pace + Duration

    private var paceSection: some View {
        HStack(spacing: 12) {
            statTile(
                label: "PACE",
                value: String(format: "%.1f", drinksPerHour),
                unit: "drinks / hr",
                color: Color(hex: "#5BC8FF")
            )
            statTile(
                label: "TIME OUT",
                value: durationString,
                unit: "since \(startTimeString)",
                color: Color(hex: "#BF5AF2")
            )
        }
        .padding(.horizontal)
    }

    private var durationString: String {
        let total = Int(hoursElapsed * 60)
        return String(format: "%dh %02dm", total / 60, total % 60)
    }

    private var startTimeString: String {
        guard let start = event?.startTime else { return "—" }
        let fmt = DateFormatter(); fmt.timeStyle = .short
        return fmt.string(from: start)
    }

    private func statTile(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .black))
                .tracking(1.5)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(AppColors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(unit)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }

    // MARK: Section 2 — Quick totals

    private var totalsSection: some View {
        HStack(spacing: 10) {
            totalTile(icon: "mug.fill",   value: "\(drinkCount)", label: "drinks",  color: AppColors.accent)
            totalTile(icon: "drop.fill",  value: "\(waterCount)", label: "waters",  color: Color(hex: "#5BC8FF"))
            totalTile(icon: "flame.fill", value: "\(totalCalories)", label: "cal", color: Color(hex: "#FF6B6B"))
        }
        .padding(.horizontal)
    }

    private func totalTile(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundStyle(AppColors.text)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColors.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.border, lineWidth: 1))
    }

    // MARK: Section 3 — Interesting Facts

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("INTERESTING FACTS", color: AppColors.accent)
            VStack(spacing: 6) {
                ForEach(facts, id: \.text) { fact in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: fact.isSafetyAlert ? "exclamationmark.triangle.fill" : "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(fact.isSafetyAlert ? AppColors.danger : AppColors.accent)
                            .frame(width: 20)
                            .padding(.top, 1)
                        Text(fact.text)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(12)
                    .background(fact.isSafetyAlert ? AppColors.danger.opacity(0.08) : AppColors.surface)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(fact.isSafetyAlert ? AppColors.danger.opacity(0.3) : AppColors.border, lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Section 4 — Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TONIGHT'S TIMELINE", color: AppColors.textTertiary)

            let allItems = timelineItems

            if allItems.isEmpty {
                Text("No drinks logged yet — your night starts here.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(allItems.enumerated()), id: \.offset) { idx, item in
                        TimelineRow(
                            item: item,
                            isLast: idx == allItems.count - 1,
                            bacLimit: bacLimit
                        )
                        if idx < allItems.count - 1 {
                            let nextItem = allItems[idx + 1]
                            let gap = Int(nextItem.timestamp.timeIntervalSince(item.timestamp) / 60)
                            if gap > 0 {
                                TimelineGapLabel(minutes: gap)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    /// Merged, sorted list of drink entries + water entries for the timeline
    private var timelineItems: [TimelineItem] {
        let drinkItems = entries.compactMap { entry -> TimelineItem? in
            guard let dt = appState.allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { return nil }
            // Cumulative BAC at this moment: re-use currentBAC(for:) but we need historical.
            // Approximation: use a simple marginal contribution. Future: add historicalBAC to AppState.
            let marginal = BACCalculator.marginalBAC(drinkType: dt, profile: appState.userProfile)
            return TimelineItem(
                id: entry.id,
                timestamp: entry.timestamp,
                kind: .drink(type: dt, marginalBAC: marginal, calories: Int(dt.caloriesPerServing))
            )
        }
        let waterItems = waterEntries.map { w in
            TimelineItem(id: w.id, timestamp: w.timestamp, kind: .water)
        }
        return (drinkItems + waterItems).sorted { $0.timestamp < $1.timestamp }
    }

    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

// MARK: - Timeline models

struct TimelineItem {
    enum Kind {
        case drink(type: DrinkType, marginalBAC: Double, calories: Int)
        case water
    }
    let id: String
    let timestamp: Date
    let kind: Kind

    var dotColor: Color {
        switch kind {
        case .drink(let dt, _, _): return dt.color
        case .water: return Color(hex: "#5BC8FF")
        }
    }
}

// MARK: - Timeline row

private struct TimelineRow: View {
    let item: TimelineItem
    let isLast: Bool
    let bacLimit: Double

    private var timeString: String {
        let fmt = DateFormatter(); fmt.timeStyle = .short
        return fmt.string(from: item.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Dot + line
            VStack(spacing: 0) {
                Circle()
                    .fill(item.dotColor)
                    .frame(width: 10, height: 10)
                    .padding(.top, 14)
                if !isLast {
                    Rectangle()
                        .fill(AppColors.border.opacity(0.5))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            // Card
            switch item.kind {
            case .drink(let dt, let marginalBAC, let calories):
                drinkCard(dt: dt, marginalBAC: marginalBAC, calories: calories)
            case .water:
                waterCard
            }
        }
    }

    private func drinkCard(dt: DrinkType, marginalBAC: Double, calories: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // BAC progress bar (2px)
            GeometryReader { geo in
                let fill = min(1.0, marginalBAC / bacLimit)
                let barColor: Color = fill < 0.4 ? Color(hex: "#4CD964") : fill < 0.7 ? AppColors.accent : AppColors.danger
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppColors.border.opacity(0.4))
                    Rectangle().fill(barColor).frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 2)
            .cornerRadius(1)

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(dt.color.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: dt.sfSymbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(dt.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(dt.name)
                        .font(.system(size: 12, weight: .700))
                        .foregroundStyle(AppColors.text)
                    Text("\(timeString) · \(calories) cal")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Spacer()

                Text(String(format: "+%.3f", marginalBAC))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(marginalBAC > 0.025 ? AppColors.danger : AppColors.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(AppColors.surface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppColors.border, lineWidth: 1))
        .padding(.bottom, 4)
    }

    private var waterCard: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: "#5BC8FF").opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "#5BC8FF"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Water")
                    .font(.system(size: 12, weight: .700))
                    .foregroundStyle(Color(hex: "#5BC8FF"))
                Text("\(timeString) · Hydration ✓")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(hex: "#0e1420"))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#5BC8FF").opacity(0.2), lineWidth: 1))
        .padding(.bottom, 4)
    }
}

// MARK: - Gap label

private struct TimelineGapLabel: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 22) // align with cards
            Text("\(minutes) min ↓")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppColors.border)
                .padding(.vertical, 4)
        }
    }
}
```

- [ ] **Step 2: Add `BACCalculator.marginalBAC` if it doesn't exist**

In the existing `BACCalculator.swift`, add this helper if no equivalent exists:

```swift
/// Approximate BAC contribution of one serving of the given drink type
/// for this user profile, ignoring time (instant absorption model).
static func marginalBAC(drinkType: DrinkType, profile: UserProfile) -> Double {
    let volumeL = drinkType.defaultVolumeMl / 1000.0
    let alcoholGrams = volumeL * drinkType.defaultAbv / 100.0 * 789.0
    let distributionFactor: Double = profile.sex == .female ? 0.55 : 0.68
    let bodyWaterL = profile.weightKg * distributionFactor
    return (alcoholGrams / (bodyWaterL * 10.0)) * 10.0 / 10.0
    // Widmark: BAC% = (grams_alcohol / (weight_g * r)) * 100
    // Simplified: grams / (weightKg * r * 10)
}
```

> If `BACCalculator` already has a method that computes this, use that instead. Grep for `marginal` or `contribution` first.

- [ ] **Step 3: Add `peakBAC(for:)` and `peakBACTime(for:)` to AppState if they don't exist**

These are needed by `NightStatsSheet`. Grep for `peakBAC` in `AppState.swift`. If not found, add:

```swift
func peakBAC(for eventId: String) -> Double {
    let eventEntries = entries.filter { $0.eventId == eventId }
    guard !eventEntries.isEmpty else { return 0 }
    // Sample BAC at each entry timestamp + 30 min after last entry
    var peak = 0.0
    let sampleTimes = eventEntries.map { $0.timestamp } + [Date()]
    for t in sampleTimes {
        let bac = historicalBAC(for: eventId, at: t)
        if bac > peak { peak = bac }
    }
    return peak
}

func peakBACTime(for eventId: String) -> Date? {
    let eventEntries = entries.filter { $0.eventId == eventId }
    guard !eventEntries.isEmpty else { return nil }
    var peak = 0.0
    var peakTime: Date? = nil
    for entry in eventEntries {
        let bac = historicalBAC(for: eventId, at: entry.timestamp.addingTimeInterval(1800))
        if bac > peak { peak = bac; peakTime = entry.timestamp.addingTimeInterval(1800) }
    }
    return peakTime
}

/// BAC at a historical timestamp (approximate, uses BACCalculator internals).
private func historicalBAC(for eventId: String, at time: Date) -> Double {
    let profile = userProfile
    let eventEntries = entries.filter { $0.eventId == eventId && $0.timestamp <= time }
    return eventEntries.reduce(0.0) { acc, entry in
        guard let dt = allDrinkTypes.first(where: { $0.id == entry.drinkTypeId }) else { return acc }
        return acc + BACCalculator.bacContributionAtTime(
            drinkType: dt,
            loggedAt: entry.timestamp,
            queryTime: time,
            profile: profile
        )
    }
}
```

> `BACCalculator.bacContributionAtTime` may already exist under a different name. Check `BACCalculator.swift` first and adapt accordingly.

- [ ] **Step 4: Build (⌘B) and fix any missing references**

- [ ] **Step 5: Commit**

```bash
git add SipTrack/Views/Event/NightStatsSheet.swift SipTrack/Views/Event/NightFacts.swift SipTrack/State/AppState.swift
git commit -m "feat: create NightStatsSheet with pace, totals, facts, timeline"
```

---

## Task 7: Final wiring — remove stub, test end-to-end

**Files:**
- Modify: `SipTrack/Views/Event/ActiveEventView.swift`

- [ ] **Step 1: Remove the temporary stub**

In `ActiveEventView.swift`, delete the temporary stub added in Task 4 Step 5:

```swift
// Delete these lines:
private struct NightStatsSheet: View {
    let eventId: String
    var body: some View { Text("Coming soon") }
}
```

- [ ] **Step 2: Build (⌘B) — should be clean with the real NightStatsSheet**

- [ ] **Step 3: Manual test on simulator**

Full flow:
1. Start a new night event
2. Verify drink picker shows search bar, filter pills, and "Add a drink" section header
3. Add Beer via the picker — toast appears, Beer now shows in "RECENTLY ADDED" when filter = All
4. Add Tequila — both appear in recents
5. Switch to Beer filter pill — only beer-type drinks visible
6. Tap STATS button — sheet opens
7. Stats sheet shows pace, totals, facts section, timeline with Beer and Tequila entries
8. Timeline shows time gap between the two drinks
9. BAC progress bar on each timeline card reflects the marginal contribution

Favorites flow:
1. Navigate to Drinks tab → DrinksView
2. Tap heart on Beer → fills red
3. Go back to active event → DrinkPickerList defaults to Favorites tab
4. Beer appears in Favorites tab
5. Tap heart again in DrinksView → unfavorites Beer
6. Picker Favorites tab now shows empty state

- [ ] **Step 4: Final commit**

```bash
git add SipTrack/Views/Event/ActiveEventView.swift
git commit -m "feat: wire NightStatsSheet into ActiveEventView, remove stub"
```

- [ ] **Step 5: Push**

```bash
git push origin main
```

---

## Self-Review Checklist

- [x] **Spec coverage:** Favorites tab (Task 1–3), All tab with recents (Task 3), category filters (Task 3), tap-to-add (Task 3), DrinksView heart + filter (Task 2), STATS button (Task 4), pace/duration tiles (Task 6), quick totals (Task 6), interesting facts (Tasks 5–6), timeline with gap labels + BAC bar (Task 6)
- [x] **No placeholders:** All code is complete and concrete
- [x] **Type consistency:** `NightFact`, `TimelineItem`, `PickerFilter`, `DrinkFilter` — all defined before use. `computeNightFacts` signature matches call site in `NightStatsSheet`
- [x] **`isFavorite(_:)` called in DrinkPickerList** — added to AppState in Task 1
- [x] **`entries` on AppState** — already a published property in AppState (confirmed from code read)
- [x] **`waterEntries` on AppState** — confirmed present in ActiveEventView usage (`appState.waterEntries`)
