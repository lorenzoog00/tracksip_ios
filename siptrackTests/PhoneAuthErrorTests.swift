//
//  PhoneAuthErrorTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

/// The test target links no Firebase package (see `googleSignInErrorDomain`), so
/// the codes are written as the raw values of `AuthErrorCode` in firebase-ios-sdk
/// 12.13.0 (FirebaseAuth/Sources/Swift/Utilities/AuthErrors.swift). The app side
/// switches on the SDK's own constants, so a drift in either shows up here.
// @MainActor: see CeilingCrossingTests.
@MainActor
struct PhoneAuthErrorTests {
    static let invalidVerificationCode = 17044
    static let sessionExpired = 17051
    static let credentialAlreadyInUse = 17025
    static let tooManyRequests = 17010
    static let invalidPhoneNumber = 17042
    static let networkError = 17020
    static let webContextCancelled = 17058
    static let quotaExceeded = 17052
    static let missingAppCredential = 17047
    static let operationNotAllowed = 17006
    static let appNotAuthorized = 17028

    static let unavailable = "Adding a number isn't available right now. Try again later."

    @Test func phoneErrorCopy() {
        #expect(FirebaseManager.phoneErrorMessage(code: Self.invalidVerificationCode)
            == "That code isn't right. Check the SMS and try again.")
        #expect(FirebaseManager.phoneErrorMessage(code: Self.sessionExpired)
            == "That code expired. Tap Resend for a new code.")
        #expect(FirebaseManager.phoneErrorMessage(code: Self.credentialAlreadyInUse)
            == "This number already belongs to another TrackSip account. If it's your other account, sign in there and remove it under Social → Phone number.")
        #expect(FirebaseManager.phoneErrorMessage(code: Self.tooManyRequests)
            == "Too many tries. Try again later.")
        #expect(FirebaseManager.phoneErrorMessage(code: Self.invalidPhoneNumber)
            == "That number doesn't look right.")
        #expect(FirebaseManager.phoneErrorMessage(code: Self.networkError) == nil)
    }

    /// SMS quota used up, or phone auth off or not set up for the app: the
    /// same "not available" line for all four.
    @Test func unavailableCodesShareOneLine() {
        #expect(FirebaseManager.phoneErrorMessage(code: Self.quotaExceeded) == Self.unavailable)
        #expect(FirebaseManager.phoneErrorMessage(code: Self.missingAppCredential) == Self.unavailable)
        #expect(FirebaseManager.phoneErrorMessage(code: Self.operationNotAllowed) == Self.unavailable)
        #expect(FirebaseManager.phoneErrorMessage(code: Self.appNotAuthorized) == Self.unavailable)
        #expect(FirebaseManager.phoneErrorText(NSError(domain: "FIRAuthErrorDomain", code: Self.quotaExceeded))
            == Self.unavailable)
    }

    /// Closing the reCAPTCHA page is a cancel, not an error: nothing is shown.
    /// Only inside Auth's domain.
    @Test func closedRecaptchaShowsNothing() {
        #expect(FirebaseManager.isPhoneCancel(code: Self.webContextCancelled))
        #expect(!FirebaseManager.isPhoneCancel(code: Self.invalidVerificationCode))
        #expect(FirebaseManager.phoneErrorMessage(code: Self.webContextCancelled) == nil)
        #expect(FirebaseManager.phoneErrorText(NSError(domain: "FIRAuthErrorDomain", code: Self.webContextCancelled)) == nil)
        let ours = NSError(domain: "FirebaseManager", code: Self.webContextCancelled,
                           userInfo: [NSLocalizedDescriptionKey: "Please sign in and try again."])
        #expect(FirebaseManager.phoneErrorText(ours) == "Please sign in and try again.")
    }

    /// "FIRAuthErrorDomain" is `AuthErrors.domain` in firebase-ios-sdk 12.13.0.
    @Test func phoneErrorTextChecksTheDomain() {
        #expect(FirebaseManager.phoneErrorText(NSError(domain: "FIRAuthErrorDomain", code: Self.invalidVerificationCode))
            == "That code isn't right. Check the SMS and try again.")
        // The same number outside Auth's domain is not an Auth code.
        let ours = NSError(domain: "FirebaseManager", code: Self.invalidVerificationCode,
                           userInfo: [NSLocalizedDescriptionKey: "Please sign in and try again."])
        #expect(FirebaseManager.phoneErrorText(ours) == "Please sign in and try again.")
        // No phone copy: the app's usual offline message.
        #expect(FirebaseManager.phoneErrorText(NSError(domain: "FIRAuthErrorDomain", code: Self.networkError))
            == "Connection error. Check your internet and try again.")
    }
}

import UIKit

/// DIAGNOSTIC (temporary): when, if ever, Auth's phone managers get set, and
/// whether UIApplication.sharedApplication is reachable off the main thread the
/// way Auth's setup reads it.
@Test nonisolated func diagAuthManagers() async {
    for second in 0..<40 {
        let state = await MainActor.run { FirebaseManager.shared.authManagerState() }
        print("DIAG t=\(second)s \(state)")
        if !state.contains("nil") { break }
        try? await Task.sleep(for: .seconds(1))
    }
    let offMain: String = await withCheckedContinuation { done in
        DispatchQueue.global().async {
            let sel = NSSelectorFromString("sharedApplication")
            let responds = UIApplication.responds(to: sel)
            let app = responds ? UIApplication.perform(sel)?.takeUnretainedValue() as? UIApplication : nil
            done.resume(returning: "responds=\(responds) app=\(app != nil)")
        }
    }
    print("DIAG off-main sharedApplication: \(offMain)")
    let onMain = await MainActor.run { UIApplication.shared.delegate.map { String(describing: type(of: $0)) } ?? "nil" }
    print("DIAG app delegate type: \(onMain)")
}
