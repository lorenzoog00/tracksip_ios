//
//  Invite.swift
//  SipTrack
//
//  Inviting a contact who isn't on TrackSip: the message with the user's friend
//  link, the WhatsApp link that carries it, and the local "Invited" mark.
//

import Foundation

enum Invite {
    /// How long a contact shows as Invited after the invite went out.
    nonisolated static let invitedFor: TimeInterval = 7 * 86400

    /// The invite text, in Spanish or English, with the friend link that opens
    /// the app or the App Store.
    nonisolated static func message(username: String, spanish: Bool) -> String {
        let link = FriendLink.shareURL(for: username).absoluteString
        return spanish
            ? "¡Únete a TrackSip! Agrégame: @\(username) \(link)"
            : "Join me on TrackSip! Add me: @\(username) \(link)"
    }

    /// `https://wa.me/<digits>?text=<message>`: WhatsApp's chat link for the
    /// number without its "+". Everything in the text but letters, digits and
    /// "-._~" is percent-encoded, so "&", "=" or "+" can't cut it short.
    nonisolated static func whatsAppURL(phone e164: String, message: String) -> URL? {
        let digits = e164.filter { character in character.isASCII && character.isWholeNumber }
        guard !digits.isEmpty else { return nil }
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let text = message.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "https://wa.me/\(digits)?text=\(text)")
    }

    /// True for an invite sent less than 7 days before `now`.
    nonisolated static func isInvited(at date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < invitedFor
    }

    /// Remembers that this contact was just invited, for this account. Marks
    /// older than 7 days are dropped on the way, so the list stays small.
    static func markInvited(contactID: String, uid: String) {
        let now = Date()
        var marks = stored(uid: uid).filter { _, at in isInvited(at: at, now: now) }
        marks[contactID] = now
        UserDefaults.standard.set(marks.mapValues { at in at.timeIntervalSince1970 }, forKey: key(uid))
    }

    static func invitedAt(contactID: String, uid: String) -> Date? {
        stored(uid: uid)[contactID]
    }

    /// Every contact this account invited in the last 7 days, read in one go.
    static func invitedContactIDs(uid: String, now: Date) -> Set<String> {
        Set(stored(uid: uid).filter { _, at in isInvited(at: at, now: now) }.keys)
    }

    /// Forgets every Invited mark of this account. Only for a deleted account:
    /// signing out keeps them.
    static func clear(uid: String) {
        UserDefaults.standard.removeObject(forKey: key(uid))
    }

    // MARK: - Private

    /// Contact id → when it was invited, under "invited.<uid>".
    private static func stored(uid: String) -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: key(uid)) ?? [:]
        var marks: [String: Date] = [:]
        for (contactID, value) in raw {
            if let seconds = value as? Double {
                marks[contactID] = Date(timeIntervalSince1970: seconds)
            }
        }
        return marks
    }

    private static func key(_ uid: String) -> String {
        "invited.\(uid)"
    }
}
