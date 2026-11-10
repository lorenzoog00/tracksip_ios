import Foundation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseCrashlytics
import CryptoKit
import Combine
import AuthenticationServices
import GoogleSignIn
import FirebaseCore
import FirebaseAppCheck
import StoreKit

@MainActor
final class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    private let auth = Auth.auth()
    private let db = Firestore.firestore()

    @Published var isSignedIn = false
    @Published var userEmail: String? = nil

    /// Fires only when the *user* ends their session — Sign Out or Delete Account.
    /// The verification flow signs in and out behind the scenes (see `signUp`);
    /// those transitions are not sign-outs and must not wipe local data.
    let userDidSignOut = PassthroughSubject<Void, Never>()

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    private init() {
        applySession(auth.currentUser)
    }

    func startListening() {
        authStateHandle = auth.addStateDidChangeListener { [weak self] auth, _ in
            // Read the live user rather than the callback's snapshot: the
            // callback can be delivered after a reload() has already flipped
            // isEmailVerified, and a stale snapshot would sign the user back out.
            Task { @MainActor in
                self?.applySession(auth.currentUser)
            }
        }
    }

    /// A session only counts as signed in once the account is actually reachable.
    /// Email/password accounts stay unusable until the verification link is
    /// clicked; Apple and Google vouch for the address themselves, and Firebase
    /// reports `isEmailVerified == false` for Apple's private relay addresses.
    nonisolated static func isUsableSession(providerIDs: [String], isEmailVerified: Bool) -> Bool {
        guard !providerIDs.isEmpty else { return false }
        if providerIDs.contains(where: { $0 != "password" }) { return true }
        return isEmailVerified
    }

    private func applySession(_ user: User?) {
        let usable = Self.isUsableSession(
            providerIDs: user?.providerData.map(\.providerID) ?? [],
            isEmailVerified: user?.isEmailVerified ?? false
        )
        isSignedIn = usable
        userEmail = usable ? user?.email : nil
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
        Crashlytics.crashlytics().setUserID(result.user.uid)
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
        Crashlytics.crashlytics().setUserID("")
        try? auth.signOut()
        userDidSignOut.send()
    }

    func refreshSession() async {
        try? await auth.currentUser?.reload()
    }

    // MARK: - OAuth (Google, Apple)

    func signInWithCredential(_ credential: AuthCredential) async throws {
        let result = try await auth.signIn(with: credential)
        isSignedIn = true
        userEmail = result.user.email
        Crashlytics.crashlytics().setUserID(result.user.uid)
    }


    // MARK: - Firestore helpers

    private func col(_ name: String) -> CollectionReference? {
        guard let uid = currentUserId() else { return nil }
        return db.collection("users").document(uid).collection(name)
    }

    // MARK: - Retry wrapper

    @discardableResult
    func attempt(_ operation: () async throws -> Void, retries: Int = 3) async -> Bool {
        for attempt in 0..<retries {
            do {
                try await operation()
                return true
            } catch {
                if attempt < retries - 1 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        return false
    }

    // MARK: - Push

    func pushEvent(_ event: NightEvent) async throws {
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
        try await col.document(event.id).setData(data, merge: true)
    }

    func deleteEvent(_ id: String) async throws {
        try await col("night_events")?.document(id).delete()
    }

    func pushEntry(_ entry: DrinkEntry) async throws {
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
        try await col.document(entry.id).setData(data, merge: true)
    }

    func deleteEntry(_ id: String) async throws {
        try await col("drink_entries")?.document(id).delete()
    }

    func pushDrinkType(_ dt: DrinkType) async throws {
        guard let col = col("drink_types") else { return }
        var data: [String: Any] = [
            "name":                dt.name,
            "alcohol_percent":     dt.defaultAbv,
            "volume_ml":           dt.defaultVolumeMl,
            "calories_per_serving": dt.caloriesPerServing,
            "is_preset":           dt.isPreset,
            "icon":                dt.icon
        ]
        if let c = dt.colorHex                          { data["color_hex"]                  = c }
        if let d = dt.defaultDrinkingDurationMinutes    { data["drinking_duration_minutes"]  = d }
        try await col.document(dt.id).setData(data, merge: true)
    }

    func deleteDrinkType(_ id: String) async throws {
        try await col("drink_types")?.document(id).delete()
    }

    func pushProfile(_ profile: UserProfile) async throws {
        guard let uid = currentUserId() else { return }
        let currentYear = Calendar.current.component(.year, from: Date())
        var data: [String: Any] = [
            "weight_kg":           profile.weightKg,
            "sex":                 profile.sex.rawValue,
            "onboarding_complete": profile.onboardingComplete
        ]
        if let h = profile.heightCm             { data["height_cm"]              = h }
        if let b = profile.birthYear            { data["age"]                    = currentYear - b }
        if let d = profile.disclaimerAcceptedAt { data["disclaimer_accepted_at"] = d.timeIntervalSince1970 * 1000 }
        if let c = profile.countryCode                           { data["country_code"]                       = c }
        if let d = profile.countryDetectionLastDismissedCode     { data["country_detection_last_dismissed"]   = d }
        data["country_detection_disabled"] = profile.countryDetectionDisabled
        data["favorite_drink_ids"] = profile.favoriteDrinkIds
        data["ai_reports_enabled"] = profile.aiReportsEnabled == true
        try await db.collection("users").document(uid).collection("profiles").document(uid)
            .setData(data, merge: true)
    }

    func pushChallenge(_ challenge: Challenge) async throws {
        guard let col = col("challenges") else { return }
        let data: [String: Any] = [
            "type":       challenge.type.rawValue,
            "target":     challenge.target,
            "start_date": challenge.startDate.timeIntervalSince1970 * 1000,
            "end_date":   challenge.endDate.timeIntervalSince1970 * 1000,
            "created_at": challenge.createdAt.timeIntervalSince1970 * 1000,
            "completed":  challenge.completed
        ]
        try await col.document(challenge.id).setData(data, merge: true)
    }

    func deleteChallenge(_ id: String) async throws {
        try await col("challenges")?.document(id).delete()
    }

    // MARK: - Pull

    struct PulledData {
        var events: [NightEvent]
        var entries: [DrinkEntry]
        var drinkTypes: [DrinkType]
        var challenges: [Challenge]
        var profile: UserProfile?
        var coachReports: [CoachReport]
    }

    func pullUserData() async -> PulledData {
        guard let uid = currentUserId() else {
            return PulledData(events: [], entries: [], drinkTypes: [], challenges: [], profile: nil, coachReports: [])
        }
        let currentYear = Calendar.current.component(.year, from: Date())
        let iso = ISO8601DateFormatter()

        let eDocs   = try? await col("night_events")?.getDocuments()
        let entDocs = try? await col("drink_entries")?.getDocuments()
        let tDocs   = try? await col("drink_types")?.getDocuments()
        let cDocs   = try? await col("challenges")?.getDocuments()
        let crDocs  = try? await db.collection("users").document(uid)
            .collection("ai_coach_reports").getDocuments()
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
                aiReport: d["ai_report"] as? String,
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
                colorHex: d["color_hex"] as? String,
                defaultDrinkingDurationMinutes: d["drinking_duration_minutes"] as? Int
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
            up.countryCode = d["country_code"] as? String
            up.countryDetectionLastDismissedCode = d["country_detection_last_dismissed"] as? String
            up.countryDetectionDisabled = d["country_detection_disabled"] as? Bool ?? false
            up.favoriteDrinkIds = d["favorite_drink_ids"] as? [String] ?? []
            up.aiReportsEnabled = d["ai_reports_enabled"] as? Bool
            profile = up
        }

        let coachReports: [CoachReport] = crDocs?.documents.compactMap { doc -> CoachReport? in
            let d = doc.data()
            guard let typeStr   = d["type"] as? String,
                  let type      = ReportType(rawValue: typeStr),
                  let startMs   = d["period_start"] as? Double,
                  let endMs     = d["period_end"] as? Double,
                  let createdMs = d["created_at"] as? Double else { return nil }
            return CoachReport(
                id: doc.documentID,
                type: type,
                periodStart: Date(timeIntervalSince1970: startMs / 1000),
                periodEnd: Date(timeIntervalSince1970: endMs / 1000),
                report: d["report"] as? String,
                createdAt: Date(timeIntervalSince1970: createdMs / 1000),
                eventAId: d["event_a_id"] as? String,
                eventBId: d["event_b_id"] as? String
            )
        } ?? []

        return PulledData(events: events, entries: entries, drinkTypes: drinkTypes,
                          challenges: challenges, profile: profile, coachReports: coachReports)
    }

    // MARK: - AI Coach Report (Firestore trigger)

    func requestCoachReport(reportId: String, data: [String: Any]) async throws {
        try await requestReport(kind: data["type"] as? String ?? "", id: reportId,
                                payload: data["request_data"] as? [String: Any] ?? [:], metadata: data)
    }

    func requestRecoveryBrief(eventId: String, data: [String: Any]) async throws {
        try await requestReport(kind: "recovery", id: eventId,
                                payload: data["request_data"] as? [String: Any] ?? [:])
    }

    func fetchRecoveryBrief(eventId: String) async -> String? {
        guard let uid = currentUserId() else { return nil }
        let doc = try? await db.collection("users").document(uid)
            .collection("night_recoveries").document(eventId).getDocument()
        guard let d = doc?.data(), d["status"] == nil else { return nil }
        return d["report"] as? String
    }

    func deleteCoachReport(reportId: String) async throws {
        guard let uid = currentUserId() else { return }
        try await db.collection("users").document(uid)
            .collection("ai_coach_reports").document(reportId).delete()
    }

    func fetchCoachReport(reportId: String) async -> String? {
        guard let uid = currentUserId() else { return nil }
        let doc = try? await db.collection("users").document(uid)
            .collection("ai_coach_reports").document(reportId).getDocument()
        return doc?.data()?["report"] as? String
    }

    func pullCoachReports() async -> [CoachReport] {
        guard let uid = currentUserId() else { return [] }
        let snap = try? await db.collection("users").document(uid)
            .collection("ai_coach_reports").getDocuments()
        return snap?.documents.compactMap { doc -> CoachReport? in
            let d = doc.data()
            guard let typeStr    = d["type"] as? String,
                  let type       = ReportType(rawValue: typeStr),
                  let startMs    = d["period_start"] as? Double,
                  let endMs      = d["period_end"] as? Double,
                  let createdMs  = d["created_at"] as? Double else { return nil }
            return CoachReport(
                id: doc.documentID,
                type: type,
                periodStart: Date(timeIntervalSince1970: startMs / 1000),
                periodEnd: Date(timeIntervalSince1970: endMs / 1000),
                report: d["report"] as? String,
                createdAt: Date(timeIntervalSince1970: createdMs / 1000),
                eventAId: d["event_a_id"] as? String,
                eventBId: d["event_b_id"] as? String
            )
        } ?? []
    }

    // MARK: - AI Report (Firestore trigger)

    func requestAiReport(eventId: String, data: [String: Any]) async throws {
        try await requestReport(kind: "night", id: eventId, payload: data)
    }

    // MARK: - Lock-screen live BAC

    /// Hands the server the lock screen's push token and this night's projected
    /// BAC curve so it can keep the number current while the app is asleep. A nil
    /// token or empty curve tells it to stop. Returns false on any failure; the
    /// lock screen then simply updates only when the app runs.
    func syncLiveActivity(token: String?, template: Any?, samples: [[String: Any]]) async -> Bool {
        guard auth.currentUser != nil else { return false }
        var data: [String: Any] = ["samples": samples]
        #if DEBUG
        data["environment"] = "sandbox"
        #else
        data["environment"] = "production"
        #endif
        if let token { data["token"] = token }
        if let template { data["template"] = template }
        do {
            _ = try await callFunction("syncLiveActivity", data: data)
            return true
        } catch {
            #if DEBUG
            print("[LiveActivity] push sync failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    var appAccountToken: UUID? {
        guard let uid = currentUserId() else { return nil }
        let hex = Array(sha256(uid).prefix(32))
        let parts = [String(hex[0..<8]), String(hex[8..<12]), String(hex[12..<16]),
                     String(hex[16..<20]), String(hex[20..<32])]
        return UUID(uuidString: parts.joined(separator: "-"))
    }

    private func requestReport(kind: String, id: String, payload: [String: Any],
                               metadata: [String: Any] = [:]) async throws {
        guard DataStore.shared.loadUserProfile().aiReportsEnabled == true else {
            throw NSError(domain: "FirebaseManager", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Enable AI reports in Profile before sharing data with Anthropic."])
        }
        var data: [String: Any] = ["kind": kind, "id": id, "payload": payload]
        data["metadata"] = metadata.filter { ["period_start", "period_end", "event_a_id", "event_b_id"].contains($0.key) }
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               StoreManager.grantsPro(productID: transaction.productID,
                                      expirationDate: transaction.expirationDate,
                                      revocationDate: transaction.revocationDate,
                                      isUpgraded: transaction.isUpgraded) {
                data["signedTransaction"] = result.jwsRepresentation
                break
            }
        }
        _ = try await callFunction("requestReport", data: data)
    }

    /// `idToken` lets a caller supply one it obtained earlier.
    ///
    /// Deleting an Apple account has to revoke Apple's authorisation, and
    /// revoking kills the refresh token — so asking for a fresh ID token here
    /// afterwards fails and the request never leaves the phone. `deleteAccount`
    /// takes its token before revoking and hands it over.
    private func callFunction(
        _ name: String, data: [String: Any], idToken: String? = nil
    ) async throws -> [String: Any] {
        guard let project = FirebaseApp.app()?.options.projectID,
              let url = URL(string: "https://us-central1-\(project).cloudfunctions.net/\(name)") else {
            throw NSError(domain: "FirebaseManager", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "This build is misconfigured. Please reinstall the app."])
        }
        let token: String
        if let idToken {
            token = idToken
        } else {
            guard let user = auth.currentUser else {
                throw NSError(domain: "FirebaseManager", code: 401,
                              userInfo: [NSLocalizedDescriptionKey: "Please sign in and try again."])
            }
            token = try await user.getIDToken(forcingRefresh: true)
        }
        let appCheck = try await appCheckToken()
        var request = URLRequest(url: url, timeoutInterval: 130)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(appCheck, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A function that is missing or not deployed answers with an HTML error
        // page rather than a callable envelope, so parsing must not be the thing
        // that fails: URLError reached the user as the catch-all "Something went
        // wrong. Please try again." and threw away the status code with it.
        let envelope = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        if let error = envelope?["error"] as? [String: Any] {
            throw NSError(domain: "FirebaseManager", code: status,
                          userInfo: [NSLocalizedDescriptionKey: error["message"] as? String ?? "Please try again."])
        }
        guard (200..<300).contains(status),
              let result = (envelope?["result"] ?? envelope?["data"]) as? [String: Any] else {
            throw NSError(domain: "FirebaseManager", code: status,
                          userInfo: [NSLocalizedDescriptionKey: Self.serverErrorMessage(function: name, status: status)])
        }
        return result
    }

    /// Shown when App Attest cannot vouch for this installation. It names App
    /// Check on purpose: this failure happens before the request is sent, so it
    /// leaves nothing in the server logs, and as the catch-all "Something went
    /// wrong" it was indistinguishable from a wrong password.
    nonisolated static let appCheckFailureMessage =
        "This app installation could not be verified (App Check). Please try again later."

    /// App Attest runs locally, so an app that is not registered for App Check
    /// in this Firebase project fails here rather than at the server.
    private func appCheckToken() async throws -> String {
        do {
            return try await AppCheck.appCheck().token(forcingRefresh: false).token
        } catch {
            throw NSError(domain: "FirebaseManager", code: 419,
                          userInfo: [NSLocalizedDescriptionKey: Self.appCheckFailureMessage])
        }
    }

    /// Message for a response that carried no callable error envelope. These are
    /// infrastructure answers rather than application errors, so the status code
    /// is the only thing that tells them apart.
    nonisolated static func serverErrorMessage(function: String, status: Int) -> String {
        switch status {
        case 404:
            return "\(function) is not available on the server. This build's backend has not been deployed."
        case 401, 403:
            return "The server rejected this request. Please sign in again and try again."
        case 500..<600:
            return "The server could not complete this request. Please try again in a moment."
        default:
            return "Unexpected server response (\(status)). Please try again."
        }
    }

    func fetchAiReport(eventId: String) async -> String? {
        guard let col = col("night_events") else { return nil }
        let doc = try? await col.document(eventId).getDocument()
        return doc?.data()?["ai_report"] as? String
    }

    // MARK: - Account deletion

    enum AccountDeletionResult { case deleted, cancelled, needsPassword, failed(String) }

    /// The backend only accepts a delete whose ID token was minted in the last
    /// five minutes, so every provider has to re-authenticate first. Apple and
    /// Google can do that interactively; a password account cannot without the
    /// password, so the caller has to collect it and call again.
    nonisolated static func requiresPasswordReauth(providerIDs: [String]) -> Bool {
        if providerIDs.contains("apple.com") || providerIDs.contains("google.com") { return false }
        return providerIDs.contains("password")
    }

    func deleteAccount(password: String? = nil) async -> AccountDeletionResult {
        guard let user = auth.currentUser else { return .failed("Not signed in") }
        if password == nil,
           Self.requiresPasswordReauth(providerIDs: user.providerData.map(\.providerID)) {
            return .needsPassword
        }
        do {
            // Firebase requires recent auth for account deletion — re-authenticate first.
            let appleAuthorizationCode = try await reauthenticate(user: user, password: password)

            // Take the token now, while the session is still whole. Revoking
            // Apple's authorisation below invalidates the refresh token, and
            // the callable cannot mint a new one after that.
            let idToken = try await user.getIDToken(forcingRefresh: true)

            // Apple requires the authorisation to be revoked when the account
            // goes. This used to happen inside `reauthenticate`, before the
            // call below — which is why deleting an Apple account never reached
            // the backend at all, while Google, having no revoke step, worked.
            if let appleAuthorizationCode {
                do {
                    try await auth.revokeToken(withAuthorizationCode: appleAuthorizationCode)
                } catch {
                    // Losing the revoke is bad, losing the account deletion is
                    // worse. Keep going and leave a trace.
                    recordUnclassifiedAuthError(error as NSError)
                }
            }

            let result = try await callFunction("deleteAccount", data: [:], idToken: idToken)
            guard result["deleted"] as? Bool == true else { return .failed("Deletion did not complete. Please try again.") }
            await signOut()
            return .deleted
        } catch let error as NSError
            where error.domain == ASAuthorizationError.errorDomain
               && error.code == ASAuthorizationError.canceled.rawValue {
            return .cancelled
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == -5 {
            return .cancelled
        } catch {
            return .failed(friendlyAuthError(error))
        }
    }

    // Switches on the whole provider set, not providerData.first: a password
    // account that later linked Google has both, and picking the wrong one
    // decides whether the user gets an interactive prompt or a password field.
    // Every failure path here throws — a silent `return` left auth_time stale
    // and the backend then refused the delete with advice the user could not
    // act on from that screen.
    /// Returns Apple's authorisation code when the account is an Apple one, for
    /// the caller to revoke **after** the account has actually been deleted.
    /// Revoking here would cut the session out from under the request that does
    /// the deleting.
    @discardableResult
    private func reauthenticate(user: FirebaseAuth.User, password: String?) async throws -> String? {
        let providerIDs = user.providerData.map(\.providerID)
        // Everything below opens a system sheet, and the caller is a button
        // inside a confirmation dialog that is still dismissing when the action
        // fires. See `presentationAnchor()`.
        let anchor = try await Self.presentationAnchor()
        if providerIDs.contains("apple.com") {
            let credential = try await AppleSignInCoordinator.shared.signIn()
            try await user.reauthenticate(with: credential)
            guard let code = AppleSignInCoordinator.shared.authorizationCode else {
                throw NSError(domain: "FirebaseManager", code: 400,
                              userInfo: [NSLocalizedDescriptionKey: "Apple authorization did not complete. Please try again."])
            }
            return code
        } else if providerIDs.contains("google.com") {
            let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
            let plistDict = plistPath.flatMap { NSDictionary(contentsOfFile: $0) }
            guard let clientID = plistDict?["CLIENT_ID"] as? String else {
                throw NSError(domain: "FirebaseManager", code: 500,
                              userInfo: [NSLocalizedDescriptionKey: "Google sign-in is not configured in this build."])
            }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: anchor)
            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(domain: "FirebaseManager", code: 400,
                              userInfo: [NSLocalizedDescriptionKey: "Google did not return an ID token. Please try again."])
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await user.reauthenticate(with: credential)
        } else if providerIDs.contains("password") {
            guard let email = user.email, let password, !password.isEmpty else {
                throw NSError(domain: "FirebaseManager", code: 401,
                              userInfo: [NSLocalizedDescriptionKey: "Please enter your password to delete your account."])
            }
            try await user.reauthenticate(
                with: EmailAuthProvider.credential(withEmail: email, password: password)
            )
        }
        return nil
    }

    // MARK: - Presentation

    /// Kept as a name the sign-in paths read well with. The logic itself lives
    /// in `PresentationAnchor`, which the ads and share paths share — they all
    /// had their own broken copy of this lookup.
    static func presentationAnchor() async throws -> UIViewController {
        try await PresentationAnchor.waitingForDismissal()
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

// MARK: - Firebase error → user-friendly string

/// Tied to the SDK's own constant so the tests can name the domain without the
/// test target having to link GoogleSignIn — and so they keep matching reality
/// if Google ever changes it.
let googleSignInErrorDomain = kGIDSignInErrorDomain

func friendlyAuthError(_ error: Error) -> String {
    let nsError = error as NSError

    // Errors we raise ourselves carry a description written for the user.
    // `PresentationAnchor` is in this list because moving that lookup out of
    // this file in #11 quietly took its message with it: a failure to find a
    // window started reading as the catch-all below again.
    if ["FirebaseManager", "PresentationAnchor", "AppleSignIn"].contains(nsError.domain) {
        return nsError.localizedDescription
    }

    // Google's own failures are not Firebase Auth codes, so they fell through
    // to the catch-all below. That is how a sign-in sheet that never opened
    // reached the user as "Something went wrong" with nothing to act on, and
    // nothing in Crashlytics to find it by either.
    if nsError.domain == googleSignInErrorDomain {
        recordUnclassifiedAuthError(nsError)
        return "Google sign-in could not be opened. Please try again."
    }

    // Firebase Auth error codes — stable across SDK versions
    switch nsError.code {
    case 17009, 17004: return "Incorrect email or password."
    case 17011:        return "No account found with that email."
    case 17007:        return "That email is already registered. Try signing in."
    case 17026:        return "Password must be at least 6 characters."
    case 17008:        return "Please enter a valid email address."
    case 17020:        return "Connection error. Check your internet and try again."
    case 17010:        return "Too many attempts. Please wait a moment and try again."
    case 17005:        return "This account has been disabled. Contact support."
    case 17014:        return "For security, please sign in again to continue."
    default:
        // Anything landing here is unclassified, so keep a copy. Without this
        // the only trace of a failure is a sentence the user cannot act on.
        recordUnclassifiedAuthError(nsError)
        return "Something went wrong. Please try again."
    }
}

/// Crashlytics throws if Firebase was never configured, which is the case in
/// the test target, so check before reaching for it.
private func recordUnclassifiedAuthError(_ error: NSError) {
    guard FirebaseApp.app() != nil else { return }
    Crashlytics.crashlytics().record(error: error)
}
