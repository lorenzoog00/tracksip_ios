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

    /// A linked phone number only finds friends. It never vouches for the
    /// account the way Apple or Google do, so an unverified email account stays
    /// locked out after adding one.
    @Test func phoneDoesNotMakeAnUnverifiedPasswordAccountUsable() {
        #expect(FirebaseManager.isUsableSession(providerIDs: ["password", "phone"], isEmailVerified: false) == false)
        #expect(FirebaseManager.isUsableSession(providerIDs: ["apple.com", "phone"], isEmailVerified: false) == true)
    }

    /// Account deletion re-authenticates with the sign-in provider, never with
    /// the phone: a password account still has to type its password.
    @Test func phoneNeverChangesTheReauthMethod() {
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["password", "phone"]) == true)
        #expect(FirebaseManager.requiresPasswordReauth(providerIDs: ["apple.com", "phone"]) == false)
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

    // MARK: - Errors the user can act on

    static let catchAll = "Something went wrong. Please try again."

    /// Deleting a Google account re-opens the Google sheet first. When that
    /// sheet failed to open, the GIDSignIn error was not a Firebase Auth code,
    /// so it fell through to the catch-all: the user read "Something went
    /// wrong" with nothing to do about it, and the call never reached the
    /// backend — the function logs showed no invocation at all.
    @Test func googleFailure_doesNotReachTheCatchAll() {
        let error = NSError(domain: googleSignInErrorDomain, code: -4)
        #expect(friendlyAuthError(error) != Self.catchAll)
    }

    @Test func firebaseManagerErrors_keepTheirOwnMessage() {
        let error = NSError(
            domain: "FirebaseManager", code: 400,
            userInfo: [NSLocalizedDescriptionKey: "Could not open the sign-in screen. Please try again."]
        )
        #expect(friendlyAuthError(error) == "Could not open the sign-in screen. Please try again.")
    }

    /// The backend's own refusal travels as a FirebaseManager error, so the
    /// reason reaches the user instead of being flattened into the catch-all.
    @Test func backendRefusal_reachesTheUserVerbatim() {
        let error = NSError(
            domain: "FirebaseManager", code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Please sign in again before deleting your account."]
        )
        #expect(friendlyAuthError(error) == "Please sign in again before deleting your account.")
    }

    @Test func knownAuthCodes_stillMapToTheirOwnWording() {
        #expect(friendlyAuthError(NSError(domain: "FIRAuthErrorDomain", code: 17011))
                == "No account found with that email.")
    }

    @Test func trulyUnknownErrors_stillFallBackToTheCatchAll() {
        #expect(friendlyAuthError(NSError(domain: "SomethingElse", code: 999)) == Self.catchAll)
    }

    /// #11 moved the window lookup into its own type, and the new domain was
    /// not on the list of ones whose message is shown — so a failure to find a
    /// window silently became "Something went wrong" again, undoing what #9
    /// had just fixed.
    @Test func presentationFailures_sayWhatHappened() {
        let error = NSError(
            domain: "PresentationAnchor", code: 400,
            userInfo: [NSLocalizedDescriptionKey: "Could not open the next screen. Please try again."]
        )
        #expect(friendlyAuthError(error) == "Could not open the next screen. Please try again.")
    }

    @Test func appleFailures_sayWhatHappened() {
        let error = NSError(
            domain: "AppleSignIn", code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Sign in with Apple was restarted. Please try again."]
        )
        #expect(friendlyAuthError(error) == "Sign in with Apple was restarted. Please try again.")
    }

    // MARK: - Starting a night from the Watch

    @Test func watchStartsANightOnlyWhenSignedInWithNoneRunning() {
        #expect(WatchBridge.mayStartNight(hasActiveNight: false, signedInUid: "u1"))
        #expect(!WatchBridge.mayStartNight(hasActiveNight: true, signedInUid: "u1"))
        #expect(!WatchBridge.mayStartNight(hasActiveNight: false, signedInUid: nil))
        #expect(!WatchBridge.mayStartNight(hasActiveNight: true, signedInUid: nil))
    }

    // MARK: - Logging deep links

    @Test func logLinksOnlyCountForTheActiveNight() {
        #expect(LogDeepLink.accepts(eventId: "e1", activeEventId: "e1"))
        #expect(!LogDeepLink.accepts(eventId: "e0", activeEventId: "e1"))
        #expect(!LogDeepLink.accepts(eventId: "e1", activeEventId: nil))
        #expect(!LogDeepLink.accepts(eventId: "", activeEventId: ""))
    }

}

// MARK: - Sign-out never waits on the push token call

// No wall-clock bounds: a stalled CI simulator (every test reporting 60+ s)
// failed timing asserts that had nothing to do with the code. Each test instead
// gives one side a deadline no stall reaches, so returning at all proves which
// side won; the time limit only stops a real hang from blocking the run.

/// Set once the work closure finishes; read after `waitAtMost` returns.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@Test(.timeLimit(.minutes(1)))
nonisolated func waitAtMostReturnsAtTheTimeoutWhileWorkHangs() async {
    let finished = Flag()
    // The work takes an hour; only the 100 ms timeout can end the wait.
    await FirebaseManager.waitAtMost(.milliseconds(100)) {
        try? await Task.sleep(for: .seconds(3600))
        finished.set()
    }
    #expect(!finished.isSet)
}

@Test(.timeLimit(.minutes(1)))
nonisolated func waitAtMostReturnsWhenWorkFinishesFirst() async {
    let finished = Flag()
    // The timeout is an hour; only the work finishing can end the wait.
    await FirebaseManager.waitAtMost(.seconds(3600)) {
        finished.set()
    }
    #expect(finished.isSet)
}
