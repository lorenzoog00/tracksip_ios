//
//  ContactPhonesTests.swift
//  siptrackTests
//

import Testing
import Foundation
import Contacts
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct ContactPhonesTests {
    private func contact(given: String = "", family: String = "", nickname: String = "",
                         organization: String = "",
                         phones: [(label: String, number: String)] = []) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.givenName = given
        contact.familyName = family
        contact.nickname = nickname
        contact.organizationName = organization
        contact.phoneNumbers = phones.map { phone in
            CNLabeledValue(label: phone.label, value: CNPhoneNumber(stringValue: phone.number))
        }
        return contact
    }

    @Test func entryPutsMobileNumbersFirst() {
        let ana = contact(given: "Ana", phones: [(CNLabelPhoneNumberMain, "55 8765 4321"),
                                                (CNLabelHome, "+1 415 555 2671"),
                                                (CNLabelPhoneNumberMobile, "55 1234 5678"),
                                                (CNLabelPhoneNumberiPhone, "81 1234 5678")])
        #expect(ContactPhones.makeEntry(ana, defaultRegion: "MX")?.phones
                == ["+525512345678", "+528112345678", "+525587654321", "+14155552671"])
    }

    @Test func entryCollapsesTheSameNumberSavedTwice() {
        let ana = contact(given: "Ana", phones: [(CNLabelHome, "+52 55 1234 5678"),
                                                (CNLabelPhoneNumberMobile, "55 1234 5678"),
                                                (CNLabelWork, "(55) 1234-5678"),
                                                (CNLabelPhoneNumberMain, "not a number")])
        #expect(ContactPhones.makeEntry(ana, defaultRegion: "MX")?.phones == ["+525512345678"])
    }

    @Test func entryIsSkippedWithoutAValidNumber() {
        #expect(ContactPhones.makeEntry(contact(given: "Ana"), defaultRegion: "MX") == nil)
        #expect(ContactPhones.makeEntry(contact(given: "Ana", phones: [(CNLabelHome, "123")]),
                                        defaultRegion: "MX") == nil)
    }

    @Test func entryNameFallsBackFromFullNameToNicknameToCompanyToNumber() {
        let phones = [(label: CNLabelPhoneNumberMobile, number: "55 1234 5678")]
        func name(_ c: CNMutableContact) -> String? { ContactPhones.makeEntry(c, defaultRegion: "MX")?.name }
        #expect(name(contact(given: "Ana", family: "López", nickname: "Anita", organization: "ACME",
                             phones: phones)) == "Ana López")
        #expect(name(contact(family: "López", nickname: "Anita", phones: phones)) == "López")
        #expect(name(contact(given: "  ", nickname: "Anita", organization: "ACME", phones: phones)) == "Anita")
        #expect(name(contact(organization: "ACME", phones: phones)) == "ACME")
        #expect(name(contact(phones: phones)) == "+52 55 1234 5678")
    }

    @Test func phonesToCheckTakesEachContactsFirstNumberFirst() {
        let e = [ContactEntry(id: "1", name: "Ana", phones: ["+525512345678", "+525587654321"]),
                 ContactEntry(id: "2", name: "Beto", phones: ["+528112345678"])]
        #expect(ContactPhones.phonesToCheck(e, ownPhone: nil, limit: 2) == ["+525512345678", "+528112345678"])
    }

    @Test func phonesToCheckGoesBackForSecondNumbersWithinTheLimit() {
        let e = [ContactEntry(id: "1", name: "Ana", phones: ["+525512345678", "+525587654321"]),
                 ContactEntry(id: "2", name: "Beto", phones: ["+528112345678"])]
        #expect(ContactPhones.phonesToCheck(e, ownPhone: nil)
                == ["+525512345678", "+528112345678", "+525587654321"])
    }

    @Test func phonesToCheckDropsOwnNumberAndDuplicates() {
        let e = [ContactEntry(id: "1", name: "Ana", phones: ["+525512345678", "+14155552671"]),
                 ContactEntry(id: "2", name: "Ana trabajo", phones: ["+525512345678"]),   // same number twice
                 ContactEntry(id: "3", name: "Yo", phones: ["+528112345678"])]           // the user
        #expect(ContactPhones.phonesToCheck(e, ownPhone: "+528112345678")
                == ["+525512345678", "+14155552671"])
    }

    @Test func invitableLeavesOutMatchedOwnAndNumberless() {
        let e = [ContactEntry(id: "1", name: "Ana", phones: ["+525512345678", "+525587654321"]),
                 ContactEntry(id: "2", name: "Beto", phones: ["+528112345678"]),
                 ContactEntry(id: "3", name: "Caro", phones: []),
                 ContactEntry(id: "4", name: "Dani", phones: ["+14155552671"])]
        // Ana is on TrackSip under her second number; Beto's number is the user's own.
        let out = ContactPhones.invitable(e, onTrackSip: ["+525587654321"], ownPhone: "+528112345678")
        #expect(out.map(\.id) == ["4"])
    }

    @Test func invitableIsSortedByNameIgnoringCaseAndAccents() {
        let e = [ContactEntry(id: "c", name: "carla", phones: ["+525511112222"]),
                 ContactEntry(id: "a", name: "ángel", phones: ["+525533334444"]),
                 ContactEntry(id: "b", name: "Beto", phones: ["+525555556666"])]
        #expect(ContactPhones.invitable(e, onTrackSip: [], ownPhone: nil).map(\.name)
                == ["ángel", "Beto", "carla"])
    }
}
