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
                                ProView(presentation: .pushed)
                            case .auth(let signUp):
                                AuthView(startOnSignUp: signUp)
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
        // Hosted here, outside the navigation stack, so a notice covers the
        // navigation bar rather than leaving it stranded above the backdrop.
        .noticeHost()
        .onChange(of: appState.reportErrorMessage) { _, message in
            guard let message else { return }
            NoticeCenter.shared.show(Notice(
                icon: "sparkles",
                title: "Report unavailable",
                message: message,
                actions: [NoticeAction("OK") { appState.reportErrorMessage = nil }]
            ))
        }
        .onChange(of: firebase.isSignedIn) { _, signedIn in
            // Re-check the country on every fresh login. Sign-out → sign-in
            // re-arms the one-shot detector; the next HomeView.task fires it.
            if signedIn { countryDetector.resetSession() }
            path = NavigationPath()
        }
        // `path` is state on RootView, so it outlives the NavigationStack that
        // reads it. The Group above tears that stack down whenever the gate
        // changes branch and builds a fresh one on the way back, and SwiftUI
        // then restores whatever route the old path still held.
        //
        // That is how signing up landed the user back on the login screen:
        // "Create Account" on the signed-out home pushes `.auth`, signing in
        // flips the branch to OnboardingView before that pushed view can pop
        // itself, and the moment onboarding finished the rebuilt stack
        // re-pushed AuthView — seconds after they had just signed in. Clearing
        // the path on a branch change keeps a route from one state out of the
        // next.
        .onChange(of: appState.userProfile.onboardingComplete) { _, _ in
            path = NavigationPath()
        }
        .sheet(item: Binding<CountryDetectionResult?>(
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
            set: { _ in countryDetector.dismissResult() }
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

