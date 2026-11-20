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
