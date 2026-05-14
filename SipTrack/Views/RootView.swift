import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var countryDetector: LocationCountryDetector
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
                        .task {
                            if appState.shouldAttemptCountryDetection {
                                countryDetector.requestOnce()
                            }
                        }
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
                            case .coach:
                                CoachView()
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
        .onChange(of: firebase.isSignedIn) { _, signedIn in
            // Re-check the country on every fresh login. Sign-out → sign-in
            // re-arms the one-shot detector; the next HomeView.task fires it.
            if signedIn { countryDetector.resetSession() }
        }
        .sheet(item: Binding(
            get: {
                // Detection runs every login, but the sheet only shows when
                // the detected country differs from the stored one and is not
                // the one the user explicitly dismissed last time.
                guard let r = countryDetector.result else { return nil }
                let code: String = {
                    switch r {
                    case .matched(let c):           return c.countryCode
                    case .unknownCountry(let c, _): return c
                    }
                }()
                return appState.shouldPromptForDetectedCountry(code) ? r : nil
            },
            set: { new in
                if new == nil { countryDetector.dismissResult() }
            }
        )) { result in
            let dismissCode: String = {
                switch result {
                case .matched(let c):           return c.countryCode
                case .unknownCountry(let c, _): return c
                }
            }()
            CountryDetectedSheet(
                result: result,
                currentCountry: appState.userProfile.legalBACLimit,
                driverType: appState.userProfile.driverType,
                onApply: { country in
                    appState.applyDetectedCountry(country)
                    countryDetector.dismissResult()
                },
                onKeepMine: {
                    appState.dismissDetectedCountry(dismissCode)
                    countryDetector.dismissResult()
                },
                onDontAskAgain: {
                    appState.disableCountryDetection()
                    countryDetector.disable()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
