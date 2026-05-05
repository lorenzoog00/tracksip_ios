import Foundation
import Supabase
import Combine

@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://zmepshcgxzpgyetahtcu.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InptZXBzaGNneHpwZ3lldGFodGN1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1MzM4NjIsImV4cCI6MjA5MjEwOTg2Mn0.kAJzvAaJFMle26o6-Jk_ePS-5cBTuhS0MhD9xGeUcKY",
        options: SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(
                emitLocalSessionAsInitialSession: true
            )
        )
    )

    @Published var isSignedIn = false
    @Published var userEmail: String? = nil

    private init() {
        isSignedIn = client.auth.currentUser != nil
        userEmail  = client.auth.currentUser?.email
    }

    // Call once on app launch — keeps isSignedIn / userEmail in sync with Supabase session
    func startListening() {
        Task {
            for await (_, session) in client.auth.authStateChanges {
                isSignedIn = session != nil
                userEmail  = session?.user.email
            }
        }
    }

    func currentUserId() -> String? {
        client.auth.currentUser?.id.uuidString
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        // Eagerly update so UI doesn't have to wait for the authStateChanges stream.
        isSignedIn = true
        userEmail = session.user.email
    }

    /// Returns true if Supabase granted a session immediately (email
    /// confirmation disabled). Returns false if the user must verify email
    /// before signing in.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password)
        if response.session != nil {
            isSignedIn = true
            userEmail = response.user.email
            return true
        }
        return false
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func refreshSession() async {
        try? await client.auth.refreshSession()
    }

    // MARK: - Push (fire-and-forget; called after every local mutation)

    func pushEvent(_ event: NightEvent) async {
        guard let userId = currentUserId() else { return }
        let row = NightEventInsert(
            id: event.id,
            user_id: userId,
            name: event.name,
            started_at: Int64(event.startTime.timeIntervalSince1970 * 1000),
            ended_at: event.endTime.map { Int64($0.timeIntervalSince1970 * 1000) },
            driving_mode: event.drivingMode,
            bac_limit: event.bacLimit,
            notes: event.notes
        )
        do { _ = try await client.from("night_events").upsert(row).execute() }
        catch { print("Supabase pushEvent error:", error) }
    }

    func deleteEvent(_ id: String) async {
        guard currentUserId() != nil else { return }
        do { _ = try await client.from("night_events").delete().eq("id", value: id).execute() }
        catch { print("Supabase deleteEvent error:", error) }
    }

    func pushEntry(_ entry: DrinkEntry) async {
        guard let userId = currentUserId() else { print("Supabase pushEntry: not signed in"); return }
        let row = DrinkEntryInsert(
            id: entry.id,
            event_id: entry.eventId,
            user_id: userId,
            drink_type_id: entry.drinkTypeId,
            timestamp_ms: Int64(entry.timestamp.timeIntervalSince1970 * 1000),
            quantity: entry.quantity,
            comment: entry.comment,
            volume_override_ml: entry.volumeOverrideMl,
            abv_override: entry.abvOverride
        )
        do { _ = try await client.from("drink_entries").upsert(row).execute() }
        catch { print("Supabase pushEntry error:", error) }
    }

    func deleteEntry(_ id: String) async {
        guard currentUserId() != nil else { print("Supabase deleteEntry: not signed in"); return }
        do { _ = try await client.from("drink_entries").delete().eq("id", value: id).execute() }
        catch { print("Supabase deleteEntry error:", error) }
    }

    func pushDrinkType(_ dt: DrinkType) async {
        guard let userId = currentUserId() else { return }
        let row = DrinkTypeInsert(
            id: dt.id,
            user_id: userId,
            name: dt.name,
            alcohol_percent: dt.defaultAbv,
            volume_ml: dt.defaultVolumeMl,
            calories_per_serving: dt.caloriesPerServing,
            icon: dt.icon,
            is_preset: dt.isPreset
        )
        _ = try? await client.from("drink_types").upsert(row).execute()
    }

    func deleteDrinkType(_ id: String) async {
        guard currentUserId() != nil else { return }
        _ = try? await client.from("drink_types").delete().eq("id", value: id).execute()
    }

    func pushProfile(_ profile: UserProfile) async {
        guard let userId = currentUserId() else { print("Supabase pushProfile: not signed in"); return }
        let currentYear = Calendar.current.component(.year, from: Date())
        let row = ProfileInsert(
            id: userId,
            weight_kg: profile.weightKg,
            height_cm: profile.heightCm,
            age: profile.birthYear.map { currentYear - $0 },
            sex: profile.sex.rawValue,
            disclaimer_accepted_at: profile.disclaimerAcceptedAt.map { Int64($0.timeIntervalSince1970 * 1000) },
            onboarding_complete: profile.onboardingComplete,
            subscription_tier: profile.subscriptionTier.rawValue,
            subscription_period: profile.subscriptionPeriod?.rawValue,
            subscription_started_at: profile.subscriptionStartedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
        do { _ = try await client.from("profiles").upsert(row).execute() }
        catch { print("Supabase pushProfile error:", error) }
    }

    // MARK: - Pull (called after sign-in to merge cloud data into local storage)

    struct PulledData {
        var events: [NightEvent]
        var entries: [DrinkEntry]
        var drinkTypes: [DrinkType]
        var challenges: [Challenge]
        var profile: UserProfile?
    }

    func pullUserData() async -> PulledData {
        guard let userId = currentUserId() else {
            return PulledData(events: [], entries: [], drinkTypes: [], challenges: [], profile: nil)
        }

        let eRows: [NightEventRow] = (try? await client
            .from("night_events").select().eq("user_id", value: userId).execute().value) ?? []

        let entRows: [DrinkEntryRow] = (try? await client
            .from("drink_entries").select().eq("user_id", value: userId).execute().value) ?? []

        let tRows: [DrinkTypeRow] = (try? await client
            .from("drink_types").select().eq("user_id", value: userId).execute().value) ?? []

        let cRows: [ChallengeRow] = (try? await client
            .from("challenges").select().eq("user_id", value: userId).execute().value) ?? []

        let pRow: ProfileRow? = try? await client
            .from("profiles").select().eq("id", value: userId).single().execute().value

        let currentYear = Calendar.current.component(.year, from: Date())
        let isoFormatter = ISO8601DateFormatter()

        let events = eRows.map { r in
            NightEvent(
                id: r.id,
                userId: userId,
                name: r.name,
                startTime: Date(timeIntervalSince1970: Double(r.started_at) / 1000.0),
                endTime: r.ended_at.map { Date(timeIntervalSince1970: Double($0) / 1000.0) },
                drivingMode: r.driving_mode ?? false,
                bacLimit: r.bac_limit,
                notes: r.notes,
                createdAt: r.created_at.flatMap { isoFormatter.date(from: $0) }
                    ?? Date(timeIntervalSince1970: Double(r.started_at) / 1000.0)
            )
        }

        let entries = entRows.map { r in
            DrinkEntry(
                id: r.id,
                eventId: r.event_id,
                drinkTypeId: r.drink_type_id,
                timestamp: Date(timeIntervalSince1970: Double(r.timestamp_ms) / 1000.0),
                quantity: r.quantity,
                comment: r.comment,
                volumeOverrideMl: r.volume_override_ml,
                abvOverride: r.abv_override
            )
        }

        let drinkTypes = tRows.map { r in
            DrinkType(
                id: r.id,
                name: r.name,
                defaultVolumeMl: r.volume_ml,
                defaultAbv: r.alcohol_percent,
                caloriesPerServing: r.calories_per_serving ?? 0,
                isPreset: r.is_preset ?? false,
                icon: r.icon ?? ""
            )
        }

        var profile: UserProfile? = nil
        if let p = pRow {
            var up = UserProfile()
            if let s = p.sex, let sex = Sex(rawValue: s) { up.sex = sex }
            if let w = p.weight_kg { up.weightKg = w }
            up.heightCm = p.height_cm
            up.birthYear = p.age.map { currentYear - $0 }
            up.onboardingComplete = p.onboarding_complete ?? false
            if let t = p.subscription_tier, let tier = SubscriptionTier(rawValue: t) { up.subscriptionTier = tier }
            if let per = p.subscription_period, let period = SubscriptionPeriod(rawValue: per) { up.subscriptionPeriod = period }
            if let s = p.subscription_started_at { up.subscriptionStartedAt = isoFormatter.date(from: s) }
            if let ts = p.disclaimer_accepted_at { up.disclaimerAcceptedAt = Date(timeIntervalSince1970: Double(ts) / 1000.0) }
            profile = up
        }

        let challenges = cRows.compactMap { r -> Challenge? in
            guard let type = ChallengeType(rawValue: r.type) else { return nil }
            return Challenge(
                id: r.id,
                type: type,
                target: r.target,
                startDate: Date(timeIntervalSince1970: Double(r.start_date) / 1000.0),
                endDate: Date(timeIntervalSince1970: Double(r.end_date) / 1000.0),
                createdAt: Date(timeIntervalSince1970: Double(r.created_at) / 1000.0),
                completed: r.completed
            )
        }

        return PulledData(events: events, entries: entries, drinkTypes: drinkTypes, challenges: challenges, profile: profile)
    }

    func pushChallenge(_ challenge: Challenge) async {
        guard let userId = currentUserId() else { return }
        let row = ChallengeInsert(
            id: challenge.id,
            user_id: userId,
            type: challenge.type.rawValue,
            target: challenge.target,
            start_date: Int64(challenge.startDate.timeIntervalSince1970 * 1000),
            end_date: Int64(challenge.endDate.timeIntervalSince1970 * 1000),
            created_at: Int64(challenge.createdAt.timeIntervalSince1970 * 1000),
            completed: challenge.completed
        )
        _ = try? await client.from("challenges").upsert(row).execute()
    }

    func deleteChallenge(_ id: String) async {
        guard currentUserId() != nil else { return }
        _ = try? await client.from("challenges").delete().eq("id", value: id).execute()
    }

    // MARK: - Account deletion

    func deleteAccount() async -> String? {
        do {
            try await client.rpc("delete_user_account").execute()
            try? await client.auth.signOut()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - DB row structs (separate Encodable/Decodable to keep column names explicit)

private struct NightEventInsert: Encodable {
    let id: String
    let user_id: String
    let name: String?
    let started_at: Int64
    let ended_at: Int64?
    let driving_mode: Bool
    let bac_limit: Double?
    let notes: String?
}

private struct NightEventRow: Decodable {
    let id: String
    let name: String?
    let started_at: Int64
    let ended_at: Int64?
    let driving_mode: Bool?
    let bac_limit: Double?
    let notes: String?
    let created_at: String?
}

private struct DrinkEntryInsert: Encodable {
    let id: String
    let event_id: String
    let user_id: String
    let drink_type_id: String
    let timestamp_ms: Int64
    let quantity: Int
    let comment: String?
    let volume_override_ml: Double?
    let abv_override: Double?
}

private struct DrinkEntryRow: Decodable {
    let id: String
    let event_id: String
    let drink_type_id: String
    let timestamp_ms: Int64
    let quantity: Int
    let comment: String?
    let volume_override_ml: Double?
    let abv_override: Double?
}

private struct DrinkTypeInsert: Encodable {
    let id: String
    let user_id: String
    let name: String
    let alcohol_percent: Double
    let volume_ml: Double
    let calories_per_serving: Double?
    let icon: String?
    let is_preset: Bool?
}

private struct DrinkTypeRow: Decodable {
    let id: String
    let name: String
    let alcohol_percent: Double
    let volume_ml: Double
    let calories_per_serving: Double?
    let icon: String?
    let is_preset: Bool?
}

private struct ProfileInsert: Encodable {
    let id: String
    let weight_kg: Double?
    let height_cm: Double?
    let age: Int?
    let sex: String?
    let disclaimer_accepted_at: Int64?
    let onboarding_complete: Bool
    let subscription_tier: String
    let subscription_period: String?
    let subscription_started_at: String?
}

private struct ProfileRow: Decodable {
    let weight_kg: Double?
    let height_cm: Double?
    let age: Int?
    let sex: String?
    let disclaimer_accepted_at: Int64?
    let onboarding_complete: Bool?
    let subscription_tier: String?
    let subscription_period: String?
    let subscription_started_at: String?
}

private struct ChallengeInsert: Encodable {
    let id: String
    let user_id: String
    let type: String
    let target: Double
    let start_date: Int64
    let end_date: Int64
    let created_at: Int64
    let completed: Bool
}

private struct ChallengeRow: Decodable {
    let id: String
    let type: String
    let target: Double
    let start_date: Int64
    let end_date: Int64
    let created_at: Int64
    let completed: Bool
}
