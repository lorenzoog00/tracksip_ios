import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if !appState.userProfile.onboardingComplete {
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
                            }
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
