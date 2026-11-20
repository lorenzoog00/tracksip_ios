//
//  ContactMatchCacheTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct ContactMatchCacheTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample() -> ContactMatchCache {
        ContactMatchCache(
            result: ContactMatchResult(
                profiles: [
                    FriendProfileSnapshot(uid: "u1", username: "ana",
                                          photoURL: URL(string: "https://example.com/ana.jpg"),
                                          avatarColor: "#FF8800"),
                    FriendProfileSnapshot(uid: "u2", username: "beto", photoURL: nil, avatarColor: ""),
                ],
                onTrackSip: ["+525587654321", "+14155552671"]
            ),
            checkedAt: t0,
            ownerPhone: "+525512345678"
        )
    }

    /// Valid for 24 hours from the check, and only for the number it was made with.
    @Test func cacheIsFreshFor24HoursWithTheSamePhone() {
        let c = ContactMatchCache(result: .init(profiles: [], onTrackSip: []), checkedAt: t0, ownerPhone: "+525512345678")
        #expect(ContactMatchCache.isFresh(c, now: t0 + 23 * 3600, currentPhone: "+525512345678"))
        #expect(!ContactMatchCache.isFresh(c, now: t0 + 24 * 3600, currentPhone: "+525512345678"))
        #expect(!ContactMatchCache.isFresh(c, now: t0 + 60, currentPhone: "+14155552671"))  // number changed
        #expect(!ContactMatchCache.isFresh(c, now: t0 + 60, currentPhone: nil))             // number removed
        #expect(!ContactMatchCache.isFresh(nil, now: t0, currentPhone: "+525512345678"))
    }

    @Test func cacheRoundTripsThroughJSON() throws {
        let cache = sample()
        let data = try JSONEncoder().encode(cache)
        let decoded = try JSONDecoder().decode(ContactMatchCache.self, from: data)
        #expect(decoded == cache)
    }

    @Test func snapshotMirrorsTheProfile() {
        let profile = FriendProfile(uid: "u1", username: "ana",
                                    photoURL: URL(string: "https://example.com/ana.jpg"), avatarColor: "#FF8800")
        #expect(FriendProfileSnapshot(profile).profile == profile)
        let bare = FriendProfile(uid: "u2", username: "beto", photoURL: nil, avatarColor: "")
        #expect(FriendProfileSnapshot(bare).profile == bare)
    }

    /// Saved per account under "contactMatch.<uid>"; another account sees nothing.
    @Test func savedPerAccountAndCleared() {
        let uid = "contact-match-test-\(UUID().uuidString)"
        let otherUid = "contact-match-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "contactMatch.\(uid)") }

        // `now` pinned to the sample's check, so the test doesn't age out.
        let now = t0 + 60
        #expect(ContactMatchCache.load(uid: uid, now: now) == nil)
        ContactMatchCache.save(sample(), uid: uid)
        #expect(ContactMatchCache.load(uid: uid, now: now) == sample())
        #expect(UserDefaults.standard.data(forKey: "contactMatch.\(uid)") != nil)
        #expect(ContactMatchCache.load(uid: otherUid, now: now) == nil)
        ContactMatchCache.clear(uid: uid)
        #expect(ContactMatchCache.load(uid: uid, now: now) == nil)
    }

    /// A check 24 hours old or more is never returned again, and loading it
    /// removes it from the phone.
    @Test func loadDropsAndRemovesAnExpiredCheck() {
        let uid = "contact-match-test-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "contactMatch.\(uid)") }

        ContactMatchCache.save(sample(), uid: uid)
        #expect(ContactMatchCache.load(uid: uid, now: t0 + 23 * 3600) == sample())
        #expect(UserDefaults.standard.data(forKey: "contactMatch.\(uid)") != nil)
        #expect(ContactMatchCache.load(uid: uid, now: t0 + 24 * 3600) == nil)
        #expect(UserDefaults.standard.data(forKey: "contactMatch.\(uid)") == nil)
    }

    /// Only the callable's own `resource-exhausted` means the day's checks are used up.
    @Test func onlyResourceExhaustedIsTheDailyLimit() {
        func error(_ status: String?, code: Int = 429) -> NSError {
            var info: [String: Any] = [NSLocalizedDescriptionKey: "x"]
            if let status { info[FirebaseManager.callableStatusKey] = status }
            return NSError(domain: "FirebaseManager", code: code, userInfo: info)
        }
        #expect(FirebaseManager.isContactCheckLimit(error("RESOURCE_EXHAUSTED")))
        #expect(!FirebaseManager.isContactCheckLimit(error("FAILED_PRECONDITION", code: 400)))
        #expect(!FirebaseManager.isContactCheckLimit(error(nil)))
        #expect(!FirebaseManager.isContactCheckLimit(URLError(.notConnectedToInternet)))
    }
}
