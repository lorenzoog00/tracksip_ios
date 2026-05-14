import Foundation

// Stores all data as JSON files in an App Group container so the Watch extension
// can read/write the same files via the shared group.
final class DataStore {

    static let shared = DataStore()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private var containerURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func url(key: String) -> URL {
        containerURL.appendingPathComponent("\(key).json")
    }

    private func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(key: key)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(key: key), options: .atomic)
    }

    // MARK: - Events

    func loadEvents() -> [NightEvent] {
        load([NightEvent].self, key: "siptrack_events") ?? []
    }

    func saveEvents(_ events: [NightEvent]) {
        save(events, key: "siptrack_events")
    }

    func createEvent(name: String?, drivingMode: Bool, bacLimit: Double?, userId: String?, startTime: Date = Date()) -> NightEvent {
        var events = loadEvents()
        let event = NightEvent(
            id: generateId(),
            userId: userId,
            name: name,
            startTime: startTime,
            endTime: nil,
            drivingMode: drivingMode,
            bacLimit: bacLimit,
            notes: nil,
            createdAt: Date()
        )
        events.append(event)
        saveEvents(events)
        return event
    }

    func updateEvent(_ event: NightEvent) {
        var events = loadEvents()
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            events[idx] = event
        }
        saveEvents(events)
    }

    func deleteEvent(_ id: String) {
        var events = loadEvents()
        events.removeAll { $0.id == id }
        saveEvents(events)
        // Cascade-delete entries and water
        var entries = loadEntries()
        entries.removeAll { $0.eventId == id }
        saveEntries(entries)
        var water = loadWaterEntries()
        water.removeAll { $0.eventId == id }
        saveWaterEntries(water)
        var food = loadFoodEntries()
        food.removeAll { $0.eventId == id }
        saveFoodEntries(food)
    }

    // MARK: - Drink Entries

    func loadEntries() -> [DrinkEntry] {
        load([DrinkEntry].self, key: "siptrack_entries") ?? []
    }

    func saveEntries(_ entries: [DrinkEntry]) {
        save(entries, key: "siptrack_entries")
    }

    func addEntry(_ entry: DrinkEntry) {
        var entries = loadEntries()
        entries.append(entry)
        saveEntries(entries)
    }

    func updateEntry(_ entry: DrinkEntry) {
        var entries = loadEntries()
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
        saveEntries(entries)
    }

    func deleteEntry(_ id: String) {
        var entries = loadEntries()
        entries.removeAll { $0.id == id }
        saveEntries(entries)
    }

    // MARK: - Water Entries

    func loadWaterEntries() -> [WaterEntry] {
        load([WaterEntry].self, key: "siptrack_water") ?? []
    }

    func saveWaterEntries(_ entries: [WaterEntry]) {
        save(entries, key: "siptrack_water")
    }

    func addWaterEntry(_ entry: WaterEntry) {
        var entries = loadWaterEntries()
        entries.append(entry)
        saveWaterEntries(entries)
    }

    func deleteWaterEntry(_ id: String) {
        var entries = loadWaterEntries()
        entries.removeAll { $0.id == id }
        saveWaterEntries(entries)
    }

    // MARK: - Food Entries

    func loadFoodEntries() -> [FoodEntry] {
        load([FoodEntry].self, key: "siptrack_food") ?? []
    }

    func saveFoodEntries(_ entries: [FoodEntry]) {
        save(entries, key: "siptrack_food")
    }

    func addFoodEntry(_ entry: FoodEntry) {
        var entries = loadFoodEntries()
        entries.append(entry)
        saveFoodEntries(entries)
    }

    func deleteFoodEntry(_ id: String) {
        var entries = loadFoodEntries()
        entries.removeAll { $0.id == id }
        saveFoodEntries(entries)
    }

    // MARK: - Drink Types

    func loadCustomDrinkTypes() -> [DrinkType] {
        load([DrinkType].self, key: "siptrack_drink_types") ?? []
    }

    func saveCustomDrinkTypes(_ types: [DrinkType]) {
        save(types, key: "siptrack_drink_types")
    }

    // MARK: - User Profile

    func loadUserProfile() -> UserProfile {
        var p = load(UserProfile.self, key: "siptrack_profile") ?? UserProfile()
        // First-launch locale seed for country + matching BAC limit. We only
        // do this once: as soon as `countryCode` exists in storage we treat
        // it as user-owned and never overwrite.
        if p.countryCode == nil, let detected = LegalBACLimits.detectFromLocale() {
            p.countryCode = detected.countryCode
            p.bacLimit = detected.limit(for: p.driverType)
            saveUserProfile(p)
        }
        return p
    }

    func saveUserProfile(_ profile: UserProfile) {
        save(profile, key: "siptrack_profile")
    }

    // MARK: - Challenges

    func loadChallenges() -> [Challenge] {
        load([Challenge].self, key: "siptrack_challenges") ?? []
    }

    func saveChallenges(_ challenges: [Challenge]) {
        save(challenges, key: "siptrack_challenges")
    }

    // MARK: - Coach Reports

    func loadCoachReports() -> [CoachReport] {
        load([CoachReport].self, key: "siptrack_coach_reports") ?? []
    }

    func saveCoachReports(_ reports: [CoachReport]) {
        save(reports, key: "siptrack_coach_reports")
    }

    // MARK: - Night Recoveries

    func loadNightRecoveries() -> [NightRecovery] {
        load([NightRecovery].self, key: "siptrack_night_recoveries") ?? []
    }

    func saveNightRecoveries(_ recoveries: [NightRecovery]) {
        save(recoveries, key: "siptrack_night_recoveries") 
    }

    // MARK: - Data Management

    func pruneOldEvents(olderThan cutoff: Date) {
        let events = loadEvents()
        let toDelete = events.filter { $0.endTime != nil && $0.endTime! < cutoff }
        for event in toDelete { deleteEvent(event.id) }
    }

    func clearAllData() {
        let keys = ["siptrack_events","siptrack_entries","siptrack_water","siptrack_drink_types","siptrack_challenges","siptrack_profile","siptrack_coach_reports","siptrack_night_recoveries","siptrack_food"]
        for key in keys {
            try? FileManager.default.removeItem(at: url(key: key))
        }
    }
}
