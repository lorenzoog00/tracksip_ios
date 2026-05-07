import SwiftUI
import StoreKit
import Combine
import UIKit
import SipTrackActivityKit

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state

    @Published var events: [NightEvent]      = []
    @Published var entries: [DrinkEntry]     = []
    @Published var waterEntries: [WaterEntry] = []
    @Published var customDrinkTypes: [DrinkType] = []
    @Published var userProfile: UserProfile  = UserProfile()
    @Published var challenges: [Challenge]   = []

    @Published var activeWarnings: [DrinkWarning] = []
    @Published var undoEntry: DrinkEntry?    = nil
    @Published var undoWaterEntry: WaterEntry? = nil
    @Published var showWaterNudge: Bool      = false
    @Published var currentUserId: String?    = nil
    @Published var shouldShowAuth: Bool      = false
    @Published var syncFailed: Bool          = false

    /// Set by ActiveEventView right after End Night so RootView can pop the
    /// active event and push SummaryView cleanly.
    @Published var pendingSummaryEventId: String? = nil

    /// Set by CreateEventView so RootView pushes the new event immediately.
    @Published var pendingEventRouteId: String? = nil

    let store: StoreManager

    private var undoTask: Task<Void, Never>?
    private var undoWaterTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var bacTimerTask: Task<Void, Never>?
    private var authCancellable: AnyCancellable?

    // MARK: - Computed

    var allDrinkTypes: [DrinkType] { DrinkType.mergedWith(custom: customDrinkTypes) }
    var isPro: Bool { store.isPro || userProfile.isPro }

    var activeEvent: NightEvent? {
        events.first { $0.isActive && $0.userId == currentUserId }
    }

    var visibleEvents: [NightEvent] {
        guard let uid = currentUserId else { return [] }
        let finished = events
            .filter { $0.endTime != nil && $0.userId == uid }
            .sorted { $0.startTime > $1.startTime }
        if isPro { return finished }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return finished.filter { $0.startTime >= cutoff }
    }

    // MARK: - Init

    init(store: StoreManager) {
        self.store = store
        currentUserId = FirebaseManager.shared.currentUserId()
        loadAll()
        if activeEvent != nil {
            WaterReminderManager.shared.schedule(intervalMinutes: userProfile.waterReminderIntervalMinutes)
        }
        authCancellable = FirebaseManager.shared.$isSignedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] isSignedIn in
                let wasSignedIn = self?.currentUserId != nil
                self?.currentUserId = FirebaseManager.shared.currentUserId()
                if wasSignedIn && !isSignedIn {
                    self?.resetProfile()
                } else if isSignedIn {
                    self?.refreshFromFirebase()
                }
            }
        refreshFromFirebase()
    }

    private func resetProfile() {
        let fresh = UserProfile()
        userProfile = fresh
        DataStore.shared.saveUserProfile(fresh)
        shouldShowAuth = true
    }

    private func loadAll() {
        let ds = DataStore.shared
        events          = ds.loadEvents()
        entries         = ds.loadEntries()
        waterEntries    = ds.loadWaterEntries()
        customDrinkTypes = ds.loadCustomDrinkTypes()
        userProfile     = ds.loadUserProfile()
        challenges      = ds.loadChallenges()
    }

    func refreshFromFirebase() {
        guard currentUserId != nil else { return }
        Task {
            let data = await FirebaseManager.shared.pullUserData()
            applyCloudData(data)
        }
    }

    // MARK: - Events

    func createEvent(name: String?, drivingMode: Bool, bacLimit: Double?, startTime: Date = Date()) -> NightEvent {
        let event = DataStore.shared.createEvent(name: name, drivingMode: drivingMode, bacLimit: bacLimit, userId: currentUserId, startTime: startTime)
        events.append(event)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        push { try await FirebaseManager.shared.pushEvent(event) }
        WatchBridge.shared.pushState()
        startLiveActivity(for: event)
        WaterReminderManager.shared.schedule(intervalMinutes: userProfile.waterReminderIntervalMinutes)
        return event
    }

    private func startBACRefreshTimer(for eventId: String) {
        bacTimerTask?.cancel()
        bacTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                updateLiveActivity(for: eventId)
            }
        }
    }

    private func startLiveActivity(for event: NightEvent) {
        print("🟡 startLiveActivity called for event: \(event.id)")
        if #available(iOS 16.2, *) {
            let ids = userProfile.liveActivityDrinkIds.isEmpty
                ? ["beer", "red-wine", "tequila", "gin-tonic"]
                : userProfile.liveActivityDrinkIds
            let quickDrinks = allDrinkTypes
                .filter { ids.contains($0.id) }
                .prefix(3)
                .map { SipTrackActivityAttributes.QuickDrink(id: $0.id, name: $0.name, symbol: $0.sfSymbol) }
            LiveActivityManager.shared.start(
                eventName: event.displayName,
                eventId: event.id,
                quickDrinks: Array(quickDrinks)
            )
            startBACRefreshTimer(for: event.id)
        }
    }

    private func updateLiveActivity(for eventId: String) {
        if #available(iOS 16.2, *) {
            guard let event = events.first(where: { $0.id == eventId }) else { return }
            let bac = currentBAC(for: eventId)
            let stage = IntoxicationStage.stage(for: bac)
            let elapsed = Int(max(0, -event.startTime.timeIntervalSinceNow) / 60)

            var safeToDriveAt: Date? = nil
            if event.drivingMode {
                let limit = event.bacLimit ?? userProfile.bacLimit
                if bac > limit {
                    let hoursUntilSafe = (bac - limit) / 0.015
                    safeToDriveAt = Date().addingTimeInterval(hoursUntilSafe * 3600)
                }
            }

            LiveActivityManager.shared.update(
                bac: bac,
                drinkCount: totalDrinks(for: eventId),
                stageName: stage.name,
                stageColorHex: stage.colorHex,
                elapsedMinutes: elapsed,
                safeToDriveAt: safeToDriveAt
            )
        }
    }

    func endEvent(_ id: String) {
        bacTimerTask?.cancel()
        bacTimerTask = nil
        updateEvent(id: id) { $0.endTime = Date() }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if #available(iOS 16.2, *) { LiveActivityManager.shared.end() }
        WaterReminderManager.shared.cancel()
        WatchBridge.shared.pushState()
    }

    func updateEventNotes(id: String, notes: String) {
        updateEvent(id: id) { $0.notes = notes }
    }

    func deleteEvent(_ id: String) {
        DataStore.shared.deleteEvent(id)
        events.removeAll { $0.id == id }
        entries.removeAll { $0.eventId == id }
        waterEntries.removeAll { $0.eventId == id }
        push { try await FirebaseManager.shared.deleteEvent(id) }
    }

    private func updateEvent(id: String, mutate: (inout NightEvent) -> Void) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        mutate(&events[idx])
        DataStore.shared.updateEvent(events[idx])
        let updated = events[idx]
        push { try await FirebaseManager.shared.pushEvent(updated) }
    }

    // MARK: - Entries

    func addDrink(
        eventId: String,
        drinkTypeId: String,
        quantity: Int = 1,
        comment: String? = nil,
        volumeOverride: Double? = nil,
        abvOverride: Double? = nil
    ) {
        let entry = DrinkEntry(
            id: generateId(),
            eventId: eventId,
            drinkTypeId: drinkTypeId,
            timestamp: Date(),
            quantity: quantity,
            comment: comment,
            volumeOverrideMl: volumeOverride,
            abvOverride: abvOverride
        )
        DataStore.shared.addEntry(entry)
        entries.append(entry)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scheduleUndo(entry)
        checkWarnings(after: entry, eventId: eventId)
        updateLiveActivity(for: eventId)
        push { try await FirebaseManager.shared.pushEntry(entry) }
        WatchBridge.shared.pushState()
    }

    func updateEntry(_ entry: DrinkEntry) {
        DataStore.shared.updateEntry(entry)
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
        push { try await FirebaseManager.shared.pushEntry(entry) }
    }

    func deleteEntry(_ id: String) {
        DataStore.shared.deleteEntry(id)
        entries.removeAll { $0.id == id }
        push { try await FirebaseManager.shared.deleteEntry(id) }
    }

    func undoLastEntry() {
        undoTask?.cancel()
        undoTask = nil
        if let e = undoEntry {
            deleteEntry(e.id)
            undoEntry = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func scheduleUndo(_ entry: DrinkEntry) {
        undoTask?.cancel()
        undoEntry = entry
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            undoEntry = nil
        }
    }

    // MARK: - Water

    func addWater(eventId: String, volumeMl: Double = 250) {
        let entry = WaterEntry(id: generateId(), eventId: eventId, timestamp: Date(), volumeMl: volumeMl)
        DataStore.shared.addWaterEntry(entry)
        waterEntries.append(entry)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scheduleUndoWater(entry)
        if activeEvent?.id == eventId {
            WaterReminderManager.shared.schedule(intervalMinutes: userProfile.waterReminderIntervalMinutes)
        }
    }

    func undoLastWaterEntry() {
        undoWaterTask?.cancel()
        undoWaterTask = nil
        if let e = undoWaterEntry {
            deleteWaterEntry(e.id)
            undoWaterEntry = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func scheduleUndoWater(_ entry: WaterEntry) {
        undoWaterTask?.cancel()
        undoWaterEntry = entry
        undoWaterTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            undoWaterEntry = nil
        }
    }

    func deleteWaterEntry(_ id: String) {
        DataStore.shared.deleteWaterEntry(id)
        waterEntries.removeAll { $0.id == id }
    }

    // MARK: - Drink Types

    func saveDrinkType(_ type: DrinkType) {
        var types = customDrinkTypes
        if let idx = types.firstIndex(where: { $0.id == type.id }) {
            types[idx] = type
        } else {
            types.append(type)
        }
        customDrinkTypes = types
        DataStore.shared.saveCustomDrinkTypes(types)
        push { try await FirebaseManager.shared.pushDrinkType(type) }
    }

    func deleteDrinkType(_ id: String) {
        customDrinkTypes.removeAll { $0.id == id }
        DataStore.shared.saveCustomDrinkTypes(customDrinkTypes)
        push { try await FirebaseManager.shared.deleteDrinkType(id) }
    }

    // MARK: - Profile

    func updateUserProfile(_ profile: UserProfile) {
        userProfile = profile
        DataStore.shared.saveUserProfile(profile)
        push { try await FirebaseManager.shared.pushProfile(profile) }
        if activeEvent != nil {
            WaterReminderManager.shared.schedule(intervalMinutes: profile.waterReminderIntervalMinutes)
        }
    }

    // MARK: - Challenges

    func addChallenge(_ challenge: Challenge) {
        challenges.append(challenge)
        DataStore.shared.saveChallenges(challenges)
        push { try await FirebaseManager.shared.pushChallenge(challenge) }
    }

    func updateChallenge(_ challenge: Challenge) {
        if let idx = challenges.firstIndex(where: { $0.id == challenge.id }) {
            challenges[idx] = challenge
        }
        DataStore.shared.saveChallenges(challenges)
        push { try await FirebaseManager.shared.pushChallenge(challenge) }
    }

    func deleteChallenge(_ id: String) {
        challenges.removeAll { $0.id == id }
        DataStore.shared.saveChallenges(challenges)
        push { try await FirebaseManager.shared.deleteChallenge(id) }
    }

    // MARK: - Warnings

    private func checkWarnings(after entry: DrinkEntry, eventId: String) {
        guard userProfile.notifications.enabled else { return }
        guard let event = events.first(where: { $0.id == eventId }) else { return }

        let eventEntries = entries.filter { $0.eventId == eventId }
        let eventWater   = waterEntries.filter { $0.eventId == eventId }
        let bac = BACCalculator.currentBAC(
            entries: eventEntries,
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime
        )
        let prevEntries = eventEntries.dropLast()
        let prevBAC = BACCalculator.currentBAC(
            entries: Array(prevEntries),
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime
        )

        let calories = eventEntries.reduce(0.0) { sum, e in
            let dt = allDrinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }

        let ctx = WarningContext(
            currentBAC: bac,
            previousBAC: prevBAC,
            drivingMode: event.drivingMode,
            bacLimit: event.bacLimit ?? userProfile.bacLimit,
            drinksLastHour: BACCalculator.drinksInLastHour(entries: eventEntries),
            totalCalories: calories,
            previousStage: IntoxicationStage.stage(for: prevBAC),
            currentStage: IntoxicationStage.stage(for: bac),
            prefs: userProfile.notifications
        )
        let warnings = buildWarnings(context: ctx)
        if !warnings.isEmpty {
            activeWarnings = warnings
        }

        let hydration = BACCalculator.hydrationLevel(waterEntries: eventWater, drinkCount: eventEntries.count)
        if hydration == .behind && userProfile.waterSuggestions {
            showWaterNudge = true
        }
    }

    func dismissWarnings() { activeWarnings = [] }
    func dismissWaterNudge() { showWaterNudge = false }

    // MARK: - Subscription sync

    func syncSubscriptionFromStore() {
        // Only upgrade the profile when StoreKit confirms pro. Never downgrade from a
        // StoreKit timeout — userProfile.isPro acts as the persistent cache so pro status
        // survives cold launches where currentEntitlements is slow.
        guard store.isPro else { return }
        var profile = userProfile
        let wasPro = profile.isPro
        profile.subscriptionTier = .pro
        if let period = store.activePeriod {
            profile.subscriptionPeriod = period
        }
        if !wasPro {
            profile.subscriptionStartedAt = Date()
        }
        updateUserProfile(profile)
    }

    // MARK: - Push helper

    private func push(_ operation: @escaping () async throws -> Void) {
        Task {
            let ok = await FirebaseManager.shared.attempt(operation)
            if !ok { syncFailed = true }
        }
    }

    func retrySync() {
        syncFailed = false
        Task {
            let data = await FirebaseManager.shared.pullUserData()
            applyCloudData(data)
            var failed = false
            let fb = FirebaseManager.shared
            for event in events        { if await !fb.attempt({ try await fb.pushEvent(event) })      { failed = true } }
            for entry in entries       { if await !fb.attempt({ try await fb.pushEntry(entry) })      { failed = true } }
            for dt in customDrinkTypes { if await !fb.attempt({ try await fb.pushDrinkType(dt) })    { failed = true } }
            for ch in challenges       { if await !fb.attempt({ try await fb.pushChallenge(ch) })    { failed = true } }
            let profile = userProfile
            if await !fb.attempt({ try await fb.pushProfile(profile) }) { failed = true }
            if failed { syncFailed = true }
        }
    }

    // MARK: - Cloud sync

    // Called after sign-in: merges cloud data into local storage without wiping local records.
    func applyCloudData(_ data: FirebaseManager.PulledData) {
        let localEventIds = Set(events.map { $0.id })
        let newEvents = data.events.filter { !localEventIds.contains($0.id) }
        if !newEvents.isEmpty {
            events.append(contentsOf: newEvents)
            DataStore.shared.saveEvents(events)
        }

        let localEntryIds = Set(entries.map { $0.id })
        let newEntries = data.entries.filter { !localEntryIds.contains($0.id) }
        if !newEntries.isEmpty {
            entries.append(contentsOf: newEntries)
            DataStore.shared.saveEntries(entries)
        }

        // Full replace: presets first so user-specific entries override them in mergedWith
        let cloudTypes = data.drinkTypes.sorted { $0.isPreset && !$1.isPreset }
        if !cloudTypes.isEmpty {
            customDrinkTypes = cloudTypes
            DataStore.shared.saveCustomDrinkTypes(customDrinkTypes)
        }

        let localChallengeIds = Set(challenges.map { $0.id })
        let newChallenges = data.challenges.filter { !localChallengeIds.contains($0.id) }
        if !newChallenges.isEmpty {
            challenges.append(contentsOf: newChallenges)
            DataStore.shared.saveChallenges(challenges)
        }

        if let cloud = data.profile {
            updateUserProfile(cloud)
        } else {
            push { try await FirebaseManager.shared.pushProfile(self.userProfile) }
        }
    }

    // MARK: - BAC helpers (for active event view)

    func currentBAC(for eventId: String) -> Double {
        guard let event = events.first(where: { $0.id == eventId }) else { return 0 }
        let eventEntries = entries.filter { $0.eventId == eventId }
        let eventWater   = waterEntries.filter { $0.eventId == eventId }
        return BACCalculator.currentBAC(
            entries: eventEntries,
            waterEntries: eventWater,
            drinkTypes: allDrinkTypes,
            profile: userProfile,
            eventStart: event.startTime
        )
    }

    func totalDrinks(for eventId: String) -> Int {
        entries.filter { $0.eventId == eventId }.reduce(0) { $0 + $1.quantity }
    }

    func totalCalories(for eventId: String) -> Double {
        entries.filter { $0.eventId == eventId }.reduce(0.0) { sum, e in
            let dt = allDrinkTypes.first { $0.id == e.drinkTypeId }
            return sum + (dt?.caloriesPerServing ?? 0) * Double(e.quantity)
        }
    }
}
