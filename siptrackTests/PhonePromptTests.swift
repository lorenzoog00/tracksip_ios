//
//  PhonePromptTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct PhonePromptTests {
    /// Social asks by itself only someone with a username, no number, and no
    /// earlier answer. All eight combinations, so a flipped condition shows up.
    @Test func asksOnlyWithUsernameNoNumberAndNoEarlierAnswer() {
        #expect(PhonePrompt.shouldPrompt(hasPhone: false, hasUsername: true, dismissed: false))

        #expect(!PhonePrompt.shouldPrompt(hasPhone: false, hasUsername: false, dismissed: false))
        #expect(!PhonePrompt.shouldPrompt(hasPhone: false, hasUsername: false, dismissed: true))
        #expect(!PhonePrompt.shouldPrompt(hasPhone: false, hasUsername: true, dismissed: true))
        #expect(!PhonePrompt.shouldPrompt(hasPhone: true, hasUsername: false, dismissed: false))
        #expect(!PhonePrompt.shouldPrompt(hasPhone: true, hasUsername: false, dismissed: true))
        #expect(!PhonePrompt.shouldPrompt(hasPhone: true, hasUsername: true, dismissed: false))
        #expect(!PhonePrompt.shouldPrompt(hasPhone: true, hasUsername: true, dismissed: true))
    }

    /// "Not now" is remembered per account, under "phonePromptDismissed.<uid>".
    @Test func dismissalIsRememberedPerAccount() {
        let uid = "phone-prompt-test-\(UUID().uuidString)"
        let otherUid = "phone-prompt-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "phonePromptDismissed.\(uid)") }

        #expect(!PhonePrompt.isDismissed(uid: uid))
        PhonePrompt.markDismissed(uid: uid)
        #expect(PhonePrompt.isDismissed(uid: uid))
        #expect(UserDefaults.standard.bool(forKey: "phonePromptDismissed.\(uid)"))
        #expect(!PhonePrompt.isDismissed(uid: otherUid))
    }

    /// Account deletion forgets the answer, for that account only.
    @Test func clearForgetsTheAnswerForThatAccountOnly() {
        let uid = "phone-prompt-test-\(UUID().uuidString)"
        let otherUid = "phone-prompt-test-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: "phonePromptDismissed.\(uid)")
            UserDefaults.standard.removeObject(forKey: "phonePromptDismissed.\(otherUid)")
        }

        PhonePrompt.markDismissed(uid: uid)
        PhonePrompt.markDismissed(uid: otherUid)
        PhonePrompt.clear(uid: uid)
        #expect(!PhonePrompt.isDismissed(uid: uid))
        #expect(UserDefaults.standard.object(forKey: "phonePromptDismissed.\(uid)") == nil)
        #expect(PhonePrompt.isDismissed(uid: otherUid))
    }

    // MARK: - Pending code

    /// A whole number of seconds, so the JSON round-trip compares exactly.
    static let sentAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let pending = PendingPhoneVerification(
        uid: "user-a", e164: "+525512345678", verificationID: "verification-id", sentAt: sentAt
    )

    /// Reopening the screen goes back to the code only for the account it was
    /// sent to, under ten minutes after, for a number the account doesn't have.
    @Test func pendingCodeIsRestorableOnlyForItsAccountWithinTenMinutes() {
        let fiveMinutesLater = Self.sentAt.addingTimeInterval(5 * 60)
        #expect(PendingPhoneVerification.isRestorable(Self.pending, uid: "user-a",
                                                      accountPhone: "+14155550123", now: fiveMinutesLater))
        #expect(PendingPhoneVerification.isRestorable(Self.pending, uid: "user-a",
                                                      accountPhone: nil, now: fiveMinutesLater))

        #expect(!PendingPhoneVerification.isRestorable(Self.pending, uid: "user-b",
                                                       accountPhone: nil, now: fiveMinutesLater))
        #expect(!PendingPhoneVerification.isRestorable(Self.pending, uid: nil,
                                                       accountPhone: nil, now: fiveMinutesLater))
        #expect(!PendingPhoneVerification.isRestorable(Self.pending, uid: "user-a", accountPhone: nil,
                                                       now: Self.sentAt.addingTimeInterval(10 * 60)))
        #expect(!PendingPhoneVerification.isRestorable(nil, uid: "user-a",
                                                       accountPhone: nil, now: fiveMinutesLater))
        // Already the account's number: the code was used.
        #expect(!PendingPhoneVerification.isRestorable(Self.pending, uid: "user-a",
                                                       accountPhone: "+525512345678", now: fiveMinutesLater))
        // A clock set back before the send would lock Resend.
        #expect(!PendingPhoneVerification.isRestorable(Self.pending, uid: "user-a", accountPhone: nil,
                                                       now: Self.sentAt.addingTimeInterval(-60)))
    }

    /// Saved under "pendingPhoneVerification", read back whole, and cleared.
    @Test func pendingCodeSavesLoadsAndClears() {
        defer { PendingPhoneVerification.clear() }

        PendingPhoneVerification.save(Self.pending)
        #expect(UserDefaults.standard.data(forKey: "pendingPhoneVerification") != nil)
        #expect(PendingPhoneVerification.load() == Self.pending)

        PendingPhoneVerification.clear()
        #expect(PendingPhoneVerification.load() == nil)
        #expect(UserDefaults.standard.object(forKey: "pendingPhoneVerification") == nil)
    }
}
