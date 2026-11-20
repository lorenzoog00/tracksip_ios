//
//  ContactPhones.swift
//  SipTrack
//
//  The address book reduced to what friend finding needs: who each contact is
//  and their numbers as E.164.
//

import Contacts
import Foundation

/// One address-book contact with at least one valid number.
nonisolated struct ContactEntry: Identifiable, Equatable, Sendable {
    let id: String          // CNContact.identifier
    let name: String
    let phones: [String]    // E.164, mobile numbers first
}

enum ContactPhones {
    /// Full or limited access already granted.
    static var isAllowed: Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited: return true
        default: return false
        }
    }

    /// Every contact (or, with limited access, every shared contact) that has a
    /// valid number, in the user's Contacts sort order. Numbers written without a
    /// country code are read as numbers of `defaultRegion`. Enumeration blocks, so
    /// call this off the main thread.
    nonisolated static func load(defaultRegion: String) throws -> [ContactEntry] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var entries: [ContactEntry] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            if let made = ContactPhones.makeEntry(contact, defaultRegion: defaultRegion) {
                entries.append(made)
            }
        }
        return entries
    }

    /// The numbers to ask the server about, at most `limit`: every contact's first
    /// number before anyone's second, so a cap cuts spare numbers, not people.
    /// Leaves out the user's own number and sends each number once.
    nonisolated static func phonesToCheck(_ entries: [ContactEntry], ownPhone: String?, limit: Int = 2000) -> [String] {
        var seen = Set<String>()
        if let ownPhone { seen.insert(ownPhone) }
        var phones: [String] = []
        let deepest = entries.map { entry in entry.phones.count }.max() ?? 0
        for rank in 0..<deepest {
            for entry in entries where rank < entry.phones.count {
                guard phones.count < limit else { return phones }
                let phone = entry.phones[rank]
                if seen.insert(phone).inserted { phones.append(phone) }
            }
        }
        return phones
    }

    /// Contacts to offer an invite: they have a number, none of their numbers is on
    /// TrackSip, and none is the user's own. Sorted by name, ignoring case and accents.
    nonisolated static func invitable(_ entries: [ContactEntry], onTrackSip: Set<String>, ownPhone: String?) -> [ContactEntry] {
        entries
            .filter { entry in
                !entry.phones.isEmpty
                    && !entry.phones.contains { phone in onTrackSip.contains(phone) || phone == ownPhone }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One contact as an entry: valid numbers as E.164 with mobile and iPhone
    /// numbers first, each number once, or nil when no number is valid.
    nonisolated static func makeEntry(_ contact: CNContact, defaultRegion: String) -> ContactEntry? {
        var mobile: [String] = []
        var other: [String] = []
        for labeled in contact.phoneNumbers {
            guard let e164 = PhoneNumbers.normalize(labeled.value.stringValue, defaultRegion: defaultRegion) else {
                continue
            }
            if labeled.label == CNLabelPhoneNumberMobile || labeled.label == CNLabelPhoneNumberiPhone {
                mobile.append(e164)
            } else {
                other.append(e164)
            }
        }
        // Mobile first, then the rest; a number saved twice keeps its first place.
        var seen = Set<String>()
        let phones = (mobile + other).filter { phone in seen.insert(phone).inserted }
        guard let first = phones.first else { return nil }
        return ContactEntry(id: contact.identifier,
                            name: displayName(contact) ?? PhoneNumbers.formatted(first),
                            phones: phones)
    }

    // MARK: - Private

    /// "Given Family", else the nickname, else the company; nil when all are blank.
    private nonisolated static func displayName(_ contact: CNContact) -> String? {
        let full = [contact.givenName, contact.familyName]
            .map { part in part.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { part in !part.isEmpty }
            .joined(separator: " ")
        for candidate in [full, contact.nickname, contact.organizationName] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
