import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import Combine

@MainActor
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    private let auth = Auth.auth()
    private let db = Firestore.firestore()

    @Published var isSignedIn = false
    @Published var userEmail: String? = nil

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private(set) var currentNonce: String?

    private init() {
        isSignedIn = auth.currentUser != nil
        userEmail = auth.currentUser?.email
    }

    func startListening() {
        authStateHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isSignedIn = user != nil
                self?.userEmail = user?.email
            }
        }
    }

    func currentUserId() -> String? {
        auth.currentUser?.uid
    }

    // MARK: - Email/Password Auth

    func signIn(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        guard result.user.isEmailVerified else {
            try? auth.signOut()
            throw NSError(domain: "FirebaseManager", code: 17095,
                          userInfo: [NSLocalizedDescriptionKey: "Please verify your email before signing in. Check your inbox for the verification link."])
        }
        isSignedIn = true
        userEmail = result.user.email
    }

    @discardableResult
    func signUp(email: String, password: String, displayName: String = "") async throws -> Bool {
        let result = try await auth.createUser(withEmail: email, password: password)
        if !displayName.isEmpty {
            let request = result.user.createProfileChangeRequest()
            request.displayName = displayName
            try? await request.commitChanges()
        }
        try? await result.user.sendEmailVerification()
        try? auth.signOut()
        return true
    }

    func resetPassword(email: String) async throws {
        try await auth.sendPasswordReset(withEmail: email)
    }

    func resendVerificationEmail(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        try await result.user.sendEmailVerification()
        try? auth.signOut()
    }

    func checkEmailVerified(email: String, password: String) async throws -> Bool {
        let result = try await auth.signIn(withEmail: email, password: password)
        try await result.user.reload()
        if result.user.isEmailVerified {
            isSignedIn = true
            userEmail = result.user.email
            return true
        }
        try? auth.signOut()
        return false
    }

    func signOut() async {
        try? auth.signOut()
    }

    func refreshSession() async {
        try? await auth.currentUser?.reload()
    }

    // MARK: - OAuth (Google, Apple)

    func signInWithCredential(_ credential: AuthCredential) async throws {
        let result = try await auth.signIn(with: credential)
        isSignedIn = true
        userEmail = result.user.email
    }

    // MARK: - Apple Sign In

    func prepareAppleSignIn() -> String {
        let raw = randomNonceString()
        currentNonce = raw
        return sha256(raw)
    }

    func handleAppleCredential(_ appleCredential: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentNonce,
              let tokenData = appleCredential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw NSError(domain: "FirebaseManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential"])
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: token,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        let result = try await auth.signIn(with: credential)
        isSignedIn = true
        userEmail = result.user.email
    }

    // MARK: - Firestore helpers

    private func col(_ name: String) -> CollectionReference? {
        guard let uid = currentUserId() else { return nil }
        return db.collection("users").document(uid).collection(name)
    }

    // MARK: - Push

    func pushEvent(_ event: NightEvent) async {
        guard let col = col("night_events") else { return }
        var data: [String: Any] = [
            "started_at": event.startTime.timeIntervalSince1970 * 1000,
            "driving_mode": event.drivingMode,
            "created_at": event.createdAt.timeIntervalSince1970 * 1000
        ]
        if let n = event.name          { data["name"]       = n }
        if let e = event.endTime       { data["ended_at"]   = e.timeIntervalSince1970 * 1000 }
        if let b = event.bacLimit      { data["bac_limit"]  = b }
        if let n = event.notes         { data["notes"]      = n }
        try? await col.document(event.id).setData(data, merge: true)
    }

    func deleteEvent(_ id: String) async {
        try? await col("night_events")?.document(id).delete()
    }

    func pushEntry(_ entry: DrinkEntry) async {
        guard let col = col("drink_entries") else { return }
        var data: [String: Any] = [
            "event_id":      entry.eventId,
            "drink_type_id": entry.drinkTypeId,
            "timestamp_ms":  entry.timestamp.timeIntervalSince1970 * 1000,
            "quantity":      entry.quantity
        ]
        if let c = entry.comment          { data["comment"]           = c }
        if let v = entry.volumeOverrideMl { data["volume_override_ml"] = v }
        if let a = entry.abvOverride      { data["abv_override"]       = a }
        try? await col.document(entry.id).setData(data, merge: true)
    }

    func deleteEntry(_ id: String) async {
        try? await col("drink_entries")?.document(id).delete()
    }

    func pushDrinkType(_ dt: DrinkType) async {
        guard let col = col("drink_types") else { return }
        var data: [String: Any] = [
            "name":                dt.name,
            "alcohol_percent":     dt.defaultAbv,
            "volume_ml":           dt.defaultVolumeMl,
            "calories_per_serving": dt.caloriesPerServing,
            "is_preset":           dt.isPreset,
            "icon":                dt.icon
        ]
        if let c = dt.colorHex { data["color_hex"] = c }
        try? await col.document(dt.id).setData(data, merge: true)
    }

    func deleteDrinkType(_ id: String) async {
        try? await col("drink_types")?.document(id).delete()
    }

    func pushProfile(_ profile: UserProfile) async {
        guard let uid = currentUserId() else { return }
        let currentYear = Calendar.current.component(.year, from: Date())
        var data: [String: Any] = [
            "weight_kg":           profile.weightKg,
            "sex":                 profile.sex.rawValue,
            "onboarding_complete": profile.onboardingComplete,
            "subscription_tier":   profile.subscriptionTier.rawValue
        ]
        if let h = profile.heightCm            { data["height_cm"]              = h }
        if let b = profile.birthYear           { data["age"]                    = currentYear - b }
        if let d = profile.disclaimerAcceptedAt { data["disclaimer_accepted_at"] = d.timeIntervalSince1970 * 1000 }
        if let p = profile.subscriptionPeriod  { data["subscription_period"]    = p.rawValue }
        if let s = profile.subscriptionStartedAt { data["subscription_started_at"] = ISO8601DateFormatter().string(from: s) }
        try? await db.collection("users").document(uid).collection("profiles").document(uid)
            .setData(data, merge: true)
    }

    func pushChallenge(_ challenge: Challenge) async {
        guard let col = col("challenges") else { return }
        let data: [String: Any] = [
            "type":       challenge.type.rawValue,
            "target":     challenge.target,
            "start_date": challenge.startDate.timeIntervalSince1970 * 1000,
            "end_date":   challenge.endDate.timeIntervalSince1970 * 1000,
            "created_at": challenge.createdAt.timeIntervalSince1970 * 1000,
            "completed":  challenge.completed
        ]
        try? await col.document(challenge.id).setData(data, merge: true)
    }

    func deleteChallenge(_ id: String) async {
        try? await col("challenges")?.document(id).delete()
    }

    // MARK: - Pull

    struct PulledData {
        var events: [NightEvent]
        var entries: [DrinkEntry]
        var drinkTypes: [DrinkType]
        var challenges: [Challenge]
        var profile: UserProfile?
    }

    func pullUserData() async -> PulledData {
        guard let uid = currentUserId() else {
            return PulledData(events: [], entries: [], drinkTypes: [], challenges: [], profile: nil)
        }
        let currentYear = Calendar.current.component(.year, from: Date())
        let iso = ISO8601DateFormatter()

        let eDocs   = try? await col("night_events")?.getDocuments()
        let entDocs = try? await col("drink_entries")?.getDocuments()
        let tDocs   = try? await col("drink_types")?.getDocuments()
        let cDocs   = try? await col("challenges")?.getDocuments()
        let pDoc    = try? await db.collection("users").document(uid)
            .collection("profiles").document(uid).getDocument()

        let events: [NightEvent] = eDocs?.documents.compactMap { doc in
            let d = doc.data()
            guard let startMs = d["started_at"] as? Double else { return nil }
            return NightEvent(
                id: doc.documentID, userId: uid,
                name: d["name"] as? String,
                startTime: Date(timeIntervalSince1970: startMs / 1000),
                endTime: (d["ended_at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                drivingMode: d["driving_mode"] as? Bool ?? false,
                bacLimit: d["bac_limit"] as? Double,
                notes: d["notes"] as? String,
                createdAt: (d["created_at"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? Date(timeIntervalSince1970: startMs / 1000)
            )
        } ?? []

        let entries: [DrinkEntry] = entDocs?.documents.compactMap { doc in
            let d = doc.data()
            guard let eventId  = d["event_id"] as? String,
                  let typeId   = d["drink_type_id"] as? String,
                  let tsMs     = d["timestamp_ms"] as? Double,
                  let qty      = d["quantity"] as? Int else { return nil }
            return DrinkEntry(
                id: doc.documentID, eventId: eventId, drinkTypeId: typeId,
                timestamp: Date(timeIntervalSince1970: tsMs / 1000),
                quantity: qty,
                comment: d["comment"] as? String,
                volumeOverrideMl: d["volume_override_ml"] as? Double,
                abvOverride: d["abv_override"] as? Double
            )
        } ?? []

        let drinkTypes: [DrinkType] = tDocs?.documents.compactMap { doc in
            let d = doc.data()
            guard let name = d["name"] as? String,
                  let abv  = d["alcohol_percent"] as? Double,
                  let vol  = d["volume_ml"] as? Double else { return nil }
            return DrinkType(
                id: doc.documentID, name: name,
                defaultVolumeMl: vol, defaultAbv: abv,
                caloriesPerServing: d["calories_per_serving"] as? Double ?? 0,
                isPreset: d["is_preset"] as? Bool ?? false,
                icon: d["icon"] as? String ?? "",
                colorHex: d["color_hex"] as? String
            )
        } ?? []

        let challenges: [Challenge] = cDocs?.documents.compactMap { doc in
            let d = doc.data()
            guard let typeStr   = d["type"] as? String,
                  let type      = ChallengeType(rawValue: typeStr),
                  let target    = d["target"] as? Double,
                  let startMs   = d["start_date"] as? Double,
                  let endMs     = d["end_date"] as? Double,
                  let createdMs = d["created_at"] as? Double else { return nil }
            return Challenge(
                id: doc.documentID, type: type, target: target,
                startDate: Date(timeIntervalSince1970: startMs / 1000),
                endDate: Date(timeIntervalSince1970: endMs / 1000),
                createdAt: Date(timeIntervalSince1970: createdMs / 1000),
                completed: d["completed"] as? Bool ?? false
            )
        } ?? []

        var profile: UserProfile? = nil
        if let pDoc, pDoc.exists, let d = pDoc.data() {
            var up = UserProfile()
            if let s = d["sex"] as? String, let sex = Sex(rawValue: s) { up.sex = sex }
            if let w = d["weight_kg"] as? Double { up.weightKg = w }
            up.heightCm  = d["height_cm"] as? Double
            up.birthYear = (d["age"] as? Int).map { currentYear - $0 }
            up.onboardingComplete = d["onboarding_complete"] as? Bool ?? false
            if let t   = d["subscription_tier"] as? String,   let tier   = SubscriptionTier(rawValue: t)     { up.subscriptionTier   = tier }
            if let per = d["subscription_period"] as? String, let period = SubscriptionPeriod(rawValue: per) { up.subscriptionPeriod = period }
            if let s   = d["subscription_started_at"] as? String { up.subscriptionStartedAt = iso.date(from: s) }
            if let ts  = d["disclaimer_accepted_at"] as? Double  { up.disclaimerAcceptedAt = Date(timeIntervalSince1970: ts / 1000) }
            profile = up
        }

        return PulledData(events: events, entries: entries, drinkTypes: drinkTypes,
                          challenges: challenges, profile: profile)
    }

    // MARK: - Account deletion

    func deleteAccount() async -> String? {
        guard let uid = currentUserId(), let user = auth.currentUser else { return "Not signed in" }
        do {
            for name in ["night_events", "drink_entries", "drink_types", "challenges", "profiles"] {
                if let snap = try? await db.collection("users").document(uid).collection(name).getDocuments() {
                    for doc in snap.documents { try? await doc.reference.delete() }
                }
            }
            try? await db.collection("users").document(uid).delete()
            try await user.delete()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Nonce helpers

    private func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        return bytes.map { String(chars[chars.index(chars.startIndex, offsetBy: Int($0) % chars.count)]) }.joined()
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }
}
