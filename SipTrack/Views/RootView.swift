import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var firebase: FirebaseManager
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if appState.shouldShowAuth {
                AuthView()
            } else if firebase.isSignedIn && !appState.userProfile.onboardingComplete {
                OnboardingView()
            } else {
                NavigationStack(path: $path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .event(let id):
                                ActiveEventView(eventId: id)
                            case .summary(let id):
                                SummaryView(eventId: id)
                            case .calendar:
                                CalendarView()
                            case .dashboard:
                                DashboardView()
                            case .challenges:
                                ChallengesView()
                            case .drinks:
                                DrinksView()
                            case .profile:
                                ProfileView()
                            case .subscription:
                                SubscriptionView()
                            case .auth:
                                AuthView()
                            }
                        }
                }
                .onChange(of: appState.pendingSummaryEventId) { _, newValue in
                    guard let eventId = newValue else { return }
                    if !path.isEmpty { path.removeLast() }
                    path.append(Route.summary(eventId))
                    appState.pendingSummaryEventId = nil
                }
                .onChange(of: appState.pendingEventRouteId) { _, newValue in
                    guard let eventId = newValue else { return }
                    path.append(Route.event(eventId))
                    appState.pendingEventRouteId = nil
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
