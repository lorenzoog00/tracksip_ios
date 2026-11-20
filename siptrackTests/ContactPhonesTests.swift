//
//  ContactPhonesTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct ContactPhonesTests {
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
