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
}
