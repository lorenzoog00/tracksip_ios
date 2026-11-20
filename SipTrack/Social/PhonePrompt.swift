//
//  PhonePrompt.swift
//  SipTrack
//
//  When the Social tab asks for a phone number by itself: once per account on
//  this phone, and only someone who has a username and no number yet. Asking
//  on demand (the Social profile, the search screen) is not limited by this.
//  Also the code that "Add your number" texted and hasn't used yet.
//

import Foundation

enum PhonePrompt {
    /// True only for someone with a username, no number, and no earlier answer.
    nonisolated static func shouldPrompt(hasPhone: Bool, hasUsername: Bool, dismissed: Bool) -> Bool {
        !hasPhone && hasUsername && !dismissed
    }

    static func isDismissed(uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(uid))
    }

    /// Kept locally, so another phone asks once more; that is intended.
    static func markDismissed(uid: String) {
        UserDefaults.standard.set(true, forKey: key(uid))
    }

    /// Forgets the answer. Only for a deleted account: signing out keeps it.
    static func clear(uid: String) {
        UserDefaults.standard.removeObject(forKey: key(uid))
    }

    private static func key(_ uid: String) -> String {
        "phonePromptDismissed.\(uid)"
    }
}

/// A code texted for "Add your number" and not used yet, kept on this phone so
/// that if iOS closes the app while the user fetches the SMS, reopening the
/// screen goes back to the code step instead of sending another (billed) SMS.
nonisolated struct PendingPhoneVerification: Codable, Equatable, Sendable {
    var uid: String
    var e164: String
    var verificationID: String
    var sentAt: Date

    /// How long a saved code is offered again after it was sent.
    nonisolated static let validFor: TimeInterval = 10 * 60

    /// True for a code sent to this account under ten minutes ago, for a number
    /// the account doesn't have yet. A clock set back before `sentAt` doesn't
    /// count either: it would lock Resend for as long as the clock is off.
    nonisolated static func isRestorable(_ pending: PendingPhoneVerification?, uid: String?,
                                         accountPhone: String?, now: Date) -> Bool {
        guard let pending, let uid, pending.uid == uid else { return false }
        let age = now.timeIntervalSince(pending.sentAt)
        return age >= 0 && age < validFor && accountPhone != pending.e164
    }

    static func load() -> PendingPhoneVerification? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PendingPhoneVerification.self, from: data)
    }

    static func save(_ pending: PendingPhoneVerification) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// One per phone, not per account: `isRestorable` checks the account.
    private static let defaultsKey = "pendingPhoneVerification"
}
