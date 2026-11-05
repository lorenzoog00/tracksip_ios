import Foundation

enum ProfileGuideTarget: Hashable {
    case water
    case calories
    case analysis
}

enum EventGuideTarget: Hashable, Identifiable {
    case water, drinks

    var id: Self { self }
}

enum Route: Hashable {
    case event(String)
    case guidedEvent(String, EventGuideTarget)
    case summary(String)
    case calendar
    case dashboard
    case challenges
    case drinks
    case guidedDrinkCalories
    case profile
    case guidedProfile(ProfileGuideTarget)
    case gettingStarted
    case subscription
    /// `signUp` decides which half of `AuthView` opens. A "Create Account"
    /// button that lands on a form headed "Sign In" reads as a dead end: the
    /// way across is a small link below the password field.
    case auth(signUp: Bool)
    case coach
}
