import Foundation

enum Route: Hashable {
    case event(String)
    case summary(String)
    case calendar
    case dashboard
    case challenges
    case drinks
    case profile
    case subscription
    /// `signUp` decides which half of `AuthView` opens. A "Create Account"
    /// button that lands on a form headed "Sign In" reads as a dead end: the
    /// way across is a small link below the password field.
    case auth(signUp: Bool)
    case coach
}
