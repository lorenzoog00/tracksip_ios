//
//  siptrackTests.swift
//  siptrackTests
//
//  Created by OROZCO Lorenzo on 24/04/26.
//

import Testing
import Foundation
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

}
