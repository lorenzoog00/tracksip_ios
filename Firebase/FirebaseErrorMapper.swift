import FirebaseAuth

func friendlyAuthError(_ error: Error) -> String {
    let nsError = error as NSError

    // Custom errors thrown by FirebaseManager carry meaningful descriptions (e.g. email-not-verified)
    if nsError.domain == "FirebaseManager" {
        return nsError.localizedDescription
    }

    if let authError = error as? AuthErrorCode {
        switch authError {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found with that email."
        case .emailAlreadyInUse:
            return "That email is already registered. Try signing in."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .invalidEmail:
            return "Please enter a valid email address."
        case .networkError:
            return "Connection error. Check your internet and try again."
        case .tooManyRequests:
            return "Too many attempts. Please wait a moment and try again."
        case .userDisabled:
            return "This account has been disabled. Contact support."
        case .requiresRecentLogin:
            return "For security, please sign in again to continue."
        default:
            break
        }
    }

    return "Something went wrong. Please try again."
}
