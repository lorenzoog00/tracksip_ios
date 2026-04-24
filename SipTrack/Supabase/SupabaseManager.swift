import Foundation

// Add the supabase-swift package via Swift Package Manager:
// https://github.com/supabase/supabase-swift
// Then uncomment the import below and all marked sections.
//
// import Supabase
//
// Replace the placeholder URL and key with your actual values:
// let supabaseURL = URL(string: "https://YOUR_PROJECT.supabase.co")!
// let supabaseKey = "YOUR_ANON_KEY"
//
// Wire it into AppState.init() after store init — call:
//   Task { await SupabaseManager.shared.signIn(email:password:) }
// and on app foreground:
//   Task { await SupabaseManager.shared.refreshSession() }

/// Mirrors the exact Supabase schema used by the Expo app.
/// Column mapping notes:
///   night_events.started_at / ended_at  → NightEvent.startTime / endTime  (Unix ms)
///   drink_entries.timestamp_ms          → DrinkEntry.timestamp             (Unix ms)
///   drink_types.alcohol_percent         → DrinkType.defaultAbv
///   drink_types.volume_ml               → DrinkType.defaultVolumeMl
///   profiles.age                        → UserProfile.birthYear            (currentYear - age)
final class SupabaseManager {
    static let shared = SupabaseManager()
    private init() {}

    // MARK: - Auth

    func currentUserId() async -> String? {
        // Uncomment when supabase-swift is added:
        // return try? await supabase.auth.session.user.id.uuidString
        return nil
    }

    func signIn(email: String, password: String) async throws {
        // try await supabase.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        // try await supabase.auth.signUp(email: email, password: password)
    }

    func signOut() async {
        // try? await supabase.auth.signOut()
    }

    func refreshSession() async {
        // try? await supabase.auth.refreshSession()
    }

    // MARK: - Push (fire-and-forget)

    func pushEvent(_ event: NightEvent) async {
        guard let userId = await currentUserId() else { return }
        let row: [String: Any] = [
            "id":           event.id,
            "user_id":      userId,
            "name":         event.name as Any,
            "started_at":   Int64(event.startTime.timeIntervalSince1970 * 1000),
            "ended_at":     event.endTime.map { Int64($0.timeIntervalSince1970 * 1000) } as Any,
            "driving_mode": event.drivingMode,
            "bac_limit":    event.bacLimit as Any,
            "notes":        event.notes as Any,
        ]
        // try? await supabase.from("night_events").upsert(row).execute()
        _ = row
    }

    func deleteEvent(_ id: String) async {
        guard await currentUserId() != nil else { return }
        // try? await supabase.from("night_events").delete().eq("id", value: id).execute()
    }

    func pushEntry(_ entry: DrinkEntry) async {
        guard let userId = await currentUserId() else { return }
        let row: [String: Any] = [
            "id":                entry.id,
            "event_id":          entry.eventId,
            "user_id":           userId,
            "drink_type_id":     entry.drinkTypeId,
            "timestamp_ms":      Int64(entry.timestamp.timeIntervalSince1970 * 1000),
            "quantity":          entry.quantity,
            "comment":           entry.comment as Any,
            "volume_override_ml": entry.volumeOverrideMl as Any,
            "abv_override":      entry.abvOverride as Any,
        ]
        // try? await supabase.from("drink_entries").upsert(row).execute()
        _ = row
    }

    func deleteEntry(_ id: String) async {
        guard await currentUserId() != nil else { return }
        // try? await supabase.from("drink_entries").delete().eq("id", value: id).execute()
    }

    func pushDrinkType(_ dt: DrinkType) async {
        guard let userId = await currentUserId() else { return }
        let row: [String: Any] = [
            "id":                  dt.id,
            "user_id":             userId,
            "name":                dt.name,
            "alcohol_percent":     dt.defaultAbv,       // ← Expo column name
            "volume_ml":           dt.defaultVolumeMl,  // ← Expo column name
            "calories_per_serving": dt.caloriesPerServing,
            "icon":                dt.icon,
            "is_preset":           dt.isPreset,
        ]
        // try? await supabase.from("drink_types").upsert(row).execute()
        _ = row
    }

    func deleteDrinkType(_ id: String) async {
        guard await currentUserId() != nil else { return }
        // try? await supabase.from("drink_types").delete().eq("id", value: id).execute()
    }

    func pushProfile(_ profile: UserProfile) async {
        guard let userId = await currentUserId() else { return }
        let currentYear = Calendar.current.component(.year, from: Date())
        let age: Int? = profile.birthYear.map { currentYear - $0 } // ← profiles.age stores age, not birth year

        let row: [String: Any?] = [
            "id":                    userId,
            "weight_kg":             profile.weightKg,
            "height_cm":             profile.heightCm,
            "age":                   age,
            "sex":                   profile.sex.rawValue,
            "disclaimer_accepted_at": profile.disclaimerAcceptedAt.map { Int64($0.timeIntervalSince1970 * 1000) },
            "onboarding_complete":   profile.onboardingComplete,
            "subscription_tier":     profile.subscriptionTier.rawValue,
            "subscription_period":   profile.subscriptionPeriod?.rawValue,
        ]
        // try? await supabase.from("profiles").upsert(row.compactMapValues { $0 }).execute()
        _ = row
    }

    // MARK: - Pull (on sign-in)

    struct PulledData {
        var events:      [NightEvent]
        var entries:     [DrinkEntry]
        var drinkTypes:  [DrinkType]
        var profile:     UserProfile?
    }

    func pullUserData() async -> PulledData {
        guard let userId = await currentUserId() else { return PulledData(events: [], entries: [], drinkTypes: [], profile: nil) }

        // When supabase-swift is integrated, replace with actual queries:
        //
        // let eventsRes  = try? await supabase.from("night_events").select().eq("user_id", value: userId).execute()
        // let entriesRes = try? await supabase.from("drink_entries").select().eq("user_id", value: userId).execute()
        // let typesRes   = try? await supabase.from("drink_types").select().eq("user_id", value: userId).execute()
        // let profileRes = try? await supabase.from("profiles").select().eq("id", value: userId).single().execute()
        //
        // Then map using the column-name conversions shown in pushEvent/pushEntry/pushDrinkType/pushProfile above,
        // plus the inverse for pull:
        //   started_at (Int64 ms) → Date(timeIntervalSince1970: ms / 1000)
        //   age (Int)             → birthYear = currentYear - age

        _ = userId
        return PulledData(events: [], entries: [], drinkTypes: [], profile: nil)
    }

    // MARK: - Account deletion

    func deleteAccount() async -> String? {
        // let result = try? await supabase.rpc("delete_user_account").execute()
        // try? await supabase.auth.signOut()
        return nil
    }
}
