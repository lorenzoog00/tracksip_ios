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

    // MARK: - Which form the user lands on

    /// "Create Account" on the signed-out home used to push the same bare
    /// `.auth` route as "Sign In", and `AuthView` always opened on Sign In.
    /// Tapping the primary call to action therefore landed on a form that
    /// could only fail, with the way across set in 14pt under the fold.
    @Test func createAccountRoute_opensTheSignUpForm() {
        #expect(Route.auth(signUp: true) != Route.auth(signUp: false))
    }

    // MARK: - Email normalisation

    @Test func email_dropsSurroundingWhitespace() {
        // What a password manager or a paste off a keyboard actually hands over.
        #expect(AuthView.normalizedEmail("  someone@example.com ") == "someone@example.com")
    }

    @Test func email_isCaseInsensitive() {
        #expect(AuthView.normalizedEmail("Someone@Example.COM") == "someone@example.com")
    }

    @Test func email_ofOnlySpacesCountsAsEmpty() {
        #expect(AuthView.normalizedEmail("   ").isEmpty)
    }

    // MARK: - When the button is live

    @Test func signUp_needsNameEmailAndSixCharacters() {
        #expect(AuthView.canSubmit(email: "a@b.com", password: "secret1", name: "Lorenzo",
                                   isSignUp: true, isLoading: false))
    }

    @Test func signUp_rejectsAShortPassword() {
        #expect(AuthView.canSubmit(email: "a@b.com", password: "12345", name: "Lorenzo",
                                   isSignUp: true, isLoading: false) == false)
    }

    @Test func signUp_rejectsANameOfOnlySpaces() {
        #expect(AuthView.canSubmit(email: "a@b.com", password: "secret1", name: "   ",
                                   isSignUp: true, isLoading: false) == false)
    }

    @Test func signIn_doesNotHoldAnOldPasswordToTodaysMinimum() {
        // The account already exists; the minimum is Firebase's problem at
        // creation time, and enforcing it here would lock the owner out.
        #expect(AuthView.canSubmit(email: "a@b.com", password: "short", name: "",
                                   isSignUp: false, isLoading: false))
    }

    @Test func signIn_doesNotNeedAName() {
        #expect(AuthView.canSubmit(email: "a@b.com", password: "secret1", name: "",
                                   isSignUp: false, isLoading: false))
    }

    @Test func anEmailOfOnlySpacesCannotBeSubmitted() {
        #expect(AuthView.canSubmit(email: "   ", password: "secret1", name: "Lorenzo",
                                   isSignUp: true, isLoading: false) == false)
    }

    @Test func nothingIsSubmittedTwiceWhileARequestIsInFlight() {
        #expect(AuthView.canSubmit(email: "a@b.com", password: "secret1", name: "Lorenzo",
                                   isSignUp: true, isLoading: true) == false)
    }

    // MARK: - Saying why the button is dead

    @Test func shortSignUpPassword_explainsItself() {
        #expect(AuthView.passwordHint(password: "123", isSignUp: true) != nil)
    }

    @Test func emptyPassword_staysQuietUntilTheyType() {
        #expect(AuthView.passwordHint(password: "", isSignUp: true) == nil)
    }

    @Test func longEnoughPassword_needsNoHint() {
        #expect(AuthView.passwordHint(password: "secret1", isSignUp: true) == nil)
    }

    @Test func signIn_neverShowsTheMinimumLengthHint() {
        #expect(AuthView.passwordHint(password: "123", isSignUp: false) == nil)
    }
}
