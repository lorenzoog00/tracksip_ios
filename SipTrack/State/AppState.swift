import SwiftUI
import Combine

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
    @Published var showWaterNudge: Bool      = false
    @Published var currentUserId: String?    = nil

    /// Set by ActiveEventView right after End Night so RootView can pop the
    /// active event and push SummaryView cleanly.
    @Published var pendingSummaryEventId: String? = nil

    let store: StoreManager

    private var undoTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var authCancellable: AnyCancellable?

    // MARK: - Computed

    var allDrinkTypes: [DrinkType] { DrinkType.mergedWith(custom: customDrinkTypes) }
    var isPro: Bool { store.isPro }

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
        currentUserId = SupabaseManager.shared.currentUserId()
        loadAll()
        authCancellable = SupabaseManager.shared.$isSignedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.currentUserId = SupabaseManager.shared.currentUserId()
            }
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

    // MARK: - Events

    func createEvent(name: String?, drivingMode: Bool, bacLimit: Double?) -> NightEvent {
        let event = DataStore.shared.createEvent(name: name, drivingMode: drivingMode, bacLimit: bacLimit, userId: currentUserId)
        events.append(event)
        Task { await SupabaseManager.shared.pushEvent(event) }
        return event
    }

    func endEvent(_ id: String) {
        updateEvent(id: id) { $0.endTime = Date() }
    }

    func updateEventNotes(id: String, notes: String) {
        updateEvent(id: id) { $0.notes = notes }
    }

    func deleteEvent(_ id: String) {
        DataStore.shared.deleteEvent(id)
        events.removeAll { $0.id == id }
        entries.removeAll { $0.eventId == id }
        waterEntries.removeAll { $0.eventId == id }
        Task { await SupabaseManager.shared.deleteEvent(id) }
    }

    private func updateEvent(id: String, mutate: (inout NightEvent) -> Void) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        mutate(&events[idx])
        DataStore.shared.updateEvent(events[idx])
        let updated = events[idx]
        Task { await SupabaseManager.shared.pushEvent(updated) }
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
        scheduleUndo(entry)
        checkWarnings(after: entry, eventId: eventId)
        Task { await SupabaseManager.shared.pushEntry(entry) }
    }

    func updateEntry(_ entry: DrinkEntry) {
        DataStore.shared.updateEntry(entry)
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
        Task { await SupabaseManager.shared.pushEntry(entry) }
    }

    func deleteEntry(_ id: String) {
        DataStore.shared.deleteEntry(id)
        entries.removeAll { $0.id == id }
        Task { await SupabaseManager.shared.deleteEntry(id) }
    }

    func undoLastEntry() {
        undoTask?.cancel()
        undoTask = nil
        if let e = undoEntry {
            deleteEntry(e.id)
            undoEntry = nil
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
        Task { await SupabaseManager.shared.pushDrinkType(type) }
    }

    func deleteDrinkType(_ id: String) {
        customDrinkTypes.removeAll { $0.id == id }
        DataStore.shared.saveCustomDrinkTypes(customDrinkTypes)
        Task { await SupabaseManager.shared.deleteDrinkType(id) }
    }

    // MARK: - Profile

    func updateUserProfile(_ profile: UserProfile) {
        userProfile = profile
        DataStore.shared.saveUserProfile(profile)
        Task { await SupabaseManager.shared.pushProfile(profile) }
    }

    // MARK: - Challenges

    func addChallenge(_ challenge: Challenge) {
        challenges.append(challenge)
        DataStore.shared.saveChallenges(challenges)
    }

    func updateChallenge(_ challenge: Challenge) {
        if let idx = challenges.firstIndex(where: { $0.id == challenge.id }) {
            challenges[idx] = challenge
        }
        DataStore.shared.saveChallenges(challenges)
    }

    func deleteChallenge(_ id: String) {
        challenges.removeAll { $0.id == id }
        DataStore.shared.saveChallenges(challenges)
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
        var profile = userProfile
        let wasPro = profile.isPro
        profile.subscriptionTier = store.isPro ? .pro : .free
        if store.isPro {
            if let period = store.activePeriod {
                profile.subscriptionPeriod = period
            }
            if !wasPro {
                profile.subscriptionStartedAt = Date()
            }
        }
        updateUserProfile(profile)
    }

    // MARK: - Cloud sync

    // Called after sign-in: merges cloud data into local storage without wiping local records.
    func applyCloudData(_ data: SupabaseManager.PulledData) {
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

        let localTypeIds = Set(customDrinkTypes.map { $0.id })
        let newTypes = data.drinkTypes.filter { !$0.isPreset && !localTypeIds.contains($0.id) }
        if !newTypes.isEmpty {
            customDrinkTypes.append(contentsOf: newTypes)
            DataStore.shared.saveCustomDrinkTypes(customDrinkTypes)
        }

        if let cloud = data.profile {
            var merged = userProfile
            merged.sex            = cloud.sex
            merged.subscriptionTier   = cloud.subscriptionTier
            merged.subscriptionPeriod = cloud.subscriptionPeriod
            if cloud.weightKg != 70    { merged.weightKg = cloud.weightKg }
            if let h = cloud.heightCm  { merged.heightCm = h }
            if let b = cloud.birthYear { merged.birthYear = b }
            if cloud.onboardingComplete { merged.onboardingComplete = true }
            updateUserProfile(merged)
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
