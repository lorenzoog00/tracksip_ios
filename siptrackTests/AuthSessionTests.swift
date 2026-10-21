//
//  AuthSessionTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

/// Apple review 2.1(a): "attempting to use any login method simply reloads the
/// login page". Signing up signs the user in, mails the verification link, then
/// signs them straight back out — and that sign-out used to look identical to a
/// user tapping Sign Out, which wiped local data and raised the full-screen auth
/// gate. These tests pin the rule that tells the two apart.
struct AuthSessionTests {

    // MARK: - Which sessions can actually use the app

    @Test func passwordAccount_isNotUsableUntilVerified() {
        #expect(FirebaseManager.isUsableSession(providerIDs: ["password"],
                                                isEmailVerified: false) == false)
    }

    @Test func passwordAccount_isUsableOnceVerified() {
        #expect(FirebaseManager.isUsableSession(providerIDs: ["password"],
                                                isEmailVerified: true) == true)
    }

    @Test func appleAccount_isUsableWithoutEmailVerification() {
        // Apple and Google verify the address themselves; Firebase still reports
        // isEmailVerified == false for Apple's private relay addresses.
        #expect(FirebaseManager.isUsableSession(providerIDs: ["apple.com"],
                                                isEmailVerified: false) == true)
    }

    @Test func googleAccount_isUsableWithoutEmailVerification() {
        #expect(FirebaseManager.isUsableSession(providerIDs: ["google.com"],
                                                isEmailVerified: false) == true)
    }

    @Test func linkedAccount_isUsableThroughItsOAuthProvider() {
        #expect(FirebaseManager.isUsableSession(providerIDs: ["password", "google.com"],
                                                isEmailVerified: false) == true)
    }

    @Test func signedOut_isNotUsable() {
        #expect(FirebaseManager.isUsableSession(providerIDs: [],
                                                isEmailVerified: false) == false)
    }

    @Test func signedOut_isNotUsableEvenIfVerifiedFlagLingers() {
        #expect(FirebaseManager.isUsableSession(providerIDs: [],
                                                isEmailVerified: true) == false)
    }
}
