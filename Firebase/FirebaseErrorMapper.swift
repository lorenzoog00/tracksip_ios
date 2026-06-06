import Foundation

func friendlyAuthError(_ error: Error) -> String {
    let nsError = error as NSError

    // Custom errors thrown by FirebaseManager carry meaningful descriptions (e.g. email-not-verified)
    if nsError.domain == "FirebaseManager" {
        return nsError.localizedDescription
    }

    // Firebase Auth error codes (FIRAuthErrorDomain) — raw values are stable across SDK versions
    switch nsError.code {
    case 17009, 17004: // wrongPassword, invalidCredential
        return "Incorrect email or password."
    case 17011:        // userNotFound
        return "No account found with that email."
    case 17007:        // emailAlreadyInUse
        return "That email is already registered. Try signing in."
    case 17026:        // weakPassword
        return "Password must be at least 6 characters."
    case 17008:        // invalidEmail
        return "Please enter a valid email address."
    case 17020:        // networkError
        return "Connection error. Check your internet and try again."
    case 17010:        // tooManyRequests
        return "Too many attempts. Please wait a moment and try again."
    case 17005:        // userDisabled
        return "This account has been disabled. Contact support."
    case 17014:        // requiresRecentLogin
        return "For security, please sign in again to continue."
    default:
        return "Something went wrong. Please try again."
    }
}
