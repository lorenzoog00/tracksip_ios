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
    case auth
    case coach
}
