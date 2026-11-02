//
//  siptrackTests.swift
//  siptrackTests
//
//  Created by OROZCO Lorenzo on 24/04/26.
//

import Testing
import Foundation
import SwiftUI
@testable import siptrack

struct siptrackTests {

    @Test func proEntitlementRequiresKnownActivePurchase() {
        let now = Date(timeIntervalSince1970: 100)
        func allowed(_ product: String, expiration: Date? = nil, revoked: Date? = nil, upgraded: Bool = false) -> Bool {
            StoreManager.grantsPro(productID: product, expirationDate: expiration,
                                   revocationDate: revoked, isUpgraded: upgraded, now: now)
        }
        let monthly = "com.lorenzoog.siptrack.pro.monthly"
        let lifetime = "com.lorenzoog.siptrack.pro.lifetime"
        #expect(allowed(monthly, expiration: now.addingTimeInterval(1)))
        #expect(!allowed(monthly, expiration: now))
        #expect(!allowed(monthly))
        #expect(!allowed("unrelated.product", expiration: now.addingTimeInterval(1)))
        #expect(allowed(lifetime))
        #expect(!allowed(lifetime, revoked: now))
        #expect(!allowed(lifetime, upgraded: true))
    }

    // MARK: - Notices
    //
    // The system alerts these replaced were each a presented UIKit controller,
    // which is why a button inside one could not open the Google sheet and
    // account deletion failed before it reached the backend.

    @Test @MainActor func showingANoticeMakesItCurrentAndDismissingClearsIt() {
        let centre = NoticeCenter.shared
        centre.dismiss()
        centre.show(Notice(icon: "trash.fill", title: "Delete?",
                           actions: [NoticeAction("Cancel", kind: .quiet)]))
        #expect(centre.current != nil)
        centre.dismiss()
        #expect(centre.current == nil)
    }

    @Test func aReplacedNoticeGetsItsOwnIdentity() {
        // The host keys off the id to restart the field and the entrance
        // animation, so two notices must not look alike to SwiftUI.
        let first = Notice(icon: "a", title: "Same", actions: [])
        let second = Notice(icon: "a", title: "Same", actions: [])
        #expect(first.id != second.id)
    }

    @Test func anActionWithAFieldReceivesWhatWasTyped() {
        var received: String?
        let action = NoticeAction("Delete forever", kind: .destructive, input: { received = $0 })
        action.handler("typed password")
        #expect(received == "typed password")
    }

    @Test func anActionWithoutAFieldIgnoresTheText() {
        var ran = false
        let action = NoticeAction("OK") { ran = true }
        action.handler("anything at all")
        #expect(ran)
    }

    @Test func toneDecidesTheColourRatherThanEachCallSite() {
        #expect(Notice.Tone.danger.color == AppColors.danger)
        #expect(Notice.Tone.water.color == AppColors.water)
        #expect(Notice.Tone.accent.color == AppColors.accent)
    }
}
