//
//  AccountDeletionTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

/// Delete Account failed with the catch-all "Something went wrong. Please try
/// again." Two independent causes sat behind it: password accounts were never
/// re-authenticated, so the backend saw a stale `auth_time` and refused; and a
/// response that was not a callable envelope — an HTML 404 from a backend that
/// is not deployed — was turned into an opaque `URLError` that threw away the
/// status code. These tests pin both rules.
struct AccountDeletionTests {

    // MARK: - Who has to re-enter a password

    @Test func passwordAccount_mustReenterPassword() {
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["password"]) == true)
    }

    @Test func appleAccount_reauthenticatesThroughApple() {
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["apple.com"]) == false)
    }

    @Test func googleAccount_reauthenticatesThroughGoogle() {
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["google.com"]) == false)
    }

    @Test func linkedAccount_prefersItsOAuthProvider() {
        // A password account that later linked Google can re-authenticate
        // interactively, so asking for the password as well would be noise.
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["password", "google.com"]) == false)
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["password", "apple.com"]) == false)
    }

    @Test func unknownProvider_doesNotAskForAPassword() {
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["phone"]) == false)
    }

    @Test func signedOut_doesNotAskForAPassword() {
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: []) == false)
    }

    // MARK: - Responses that carry no callable envelope

    @Test func missingFunction_namesItAndSaysTheBackendIsNotDeployed() {
        let message = FirebaseManager.serverErrorMessage(function: "deleteAccount", status: 404)
        #expect(message.contains("deleteAccount"))
        #expect(message.contains("not been deployed"))
    }

    @Test func rejectedRequest_asksTheUserToSignInAgain() {
        #expect(FirebaseManager.serverErrorMessage(function: "deleteAccount", status: 403)
                    .contains("sign in again"))
    }

    @Test func serverFailure_asksTheUserToRetry() {
        #expect(FirebaseManager.serverErrorMessage(function: "deleteAccount", status: 503)
                    .contains("try again"))
    }

    @Test func unexpectedStatus_isReportedWithItsCode() {
        #expect(FirebaseManager.serverErrorMessage(function: "deleteAccount", status: 418)
                    .contains("418"))
    }

    /// No HTTP response at all still has to produce something the user can read,
    /// because this is the path that used to surface as "Something went wrong".
    @Test func noStatusCodeAtAll_stillProducesAMessage() {
        #expect(!FirebaseManager.serverErrorMessage(function: "deleteAccount", status: 0).isEmpty)
    }

    /// Whatever the status, the message must never be the old catch-all: that
    /// string is what made this undiagnosable in the first place.
    @Test func noStatus_fallsBackToSomethingSpecific() {
        for status in [0, 404, 401, 403, 500, 503, 418] {
            let message = FirebaseManager.serverErrorMessage(function: "deleteAccount", status: status)
            #expect(message != "Something went wrong. Please try again.")
        }
    }
}
