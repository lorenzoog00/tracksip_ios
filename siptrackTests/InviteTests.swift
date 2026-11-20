//
//  InviteTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct InviteTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func inviteMessages() {
        #expect(Invite.message(username: "lalo", spanish: true)
            == "¡Únete a TrackSip! Agrégame: @lalo https://tracksip.online/u/lalo")
        #expect(Invite.message(username: "lalo", spanish: false)
            == "Join me on TrackSip! Add me: @lalo https://tracksip.online/u/lalo")
    }

    @Test func whatsAppURLUsesDigitsAndEncodesText() {
        let url = Invite.whatsAppURL(phone: "+525512345678", message: "¡Hola! @lalo https://tracksip.online/u/lalo")
        #expect(url?.absoluteString.hasPrefix("https://wa.me/525512345678?text=") == true)
        #expect(URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            == "¡Hola! @lalo https://tracksip.online/u/lalo")
    }

    /// "&", "=" and "+" in the text must not cut or change it.
    @Test func whatsAppURLKeepsQuerySymbolsInsideTheText() {
        let text = "a&b=c+d #1?"
        let url = Invite.whatsAppURL(phone: "+14155552671", message: text)
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        #expect(items?.count == 1)
        #expect(items?.first?.name == "text")
        #expect(items?.first?.value == text)
    }

    @Test func invitedLastsSevenDays() {
        #expect(Invite.isInvited(at: t0, now: t0 + 6 * 86400))
        #expect(!Invite.isInvited(at: t0, now: t0 + 7 * 86400))
        #expect(!Invite.isInvited(at: nil, now: t0))
    }

    /// Marks are kept per account under "invited.<uid>", by contact id.
    @Test func invitedIsRememberedPerAccountAndContact() {
        let uid = "invite-test-\(UUID().uuidString)"
        let otherUid = "invite-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "invited.\(uid)") }

        #expect(Invite.invitedAt(contactID: "c1", uid: uid) == nil)
        Invite.markInvited(contactID: "c1", uid: uid)
        let at = Invite.invitedAt(contactID: "c1", uid: uid)
        #expect(at != nil)
        #expect(Invite.isInvited(at: at, now: Date()))
        #expect(Invite.invitedContactIDs(uid: uid, now: Date()) == ["c1"])
        #expect(Invite.invitedAt(contactID: "c2", uid: uid) == nil)
        #expect(Invite.invitedAt(contactID: "c1", uid: otherUid) == nil)
        #expect(UserDefaults.standard.dictionary(forKey: "invited.\(uid)") != nil)
    }
}
