//
//  PhonePrompt.swift
//  SipTrack
//
//  When the Social tab asks for a phone number by itself: once per account on
//  this phone, and only someone who has a username and no number yet. Asking
//  on demand (the Social profile, the search screen) is not limited by this.
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

    private static func key(_ uid: String) -> String {
        "phonePromptDismissed.\(uid)"
    }
}
