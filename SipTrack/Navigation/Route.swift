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
    /// The night screen opening straight into its camera (the lock-screen button).
    /// The UUID is the tap's `CameraRequest.id`: a new tap is a new route, so a
    /// fresh night screen opens its camera even when one is already on top.
    case eventCamera(String, UUID)
    case guidedEvent(String, EventGuideTarget)
    case summary(String)
    case stories(String)
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
