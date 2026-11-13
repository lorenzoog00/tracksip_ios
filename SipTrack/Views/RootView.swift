import SwiftUI

/// Shown for the second or two between signing in and the cloud profile
/// landing. Deliberately says nothing about setting anything up: for the
/// returning user this is the common case, and it is about to disappear.
struct RestoringProfileView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .tint(AppColors.accent)
                    .scaleEffect(1.2)
                Text("Getting your account")
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

/// Covers the whole app when this version is below `RequiredUpdate`'s
/// minimum. No close button: the only way out is the App Store.
struct UpdateRequiredView: View {
    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.accent)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text("Update required")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.text)
                    Text("This version of Tracksip is no longer supported. Update to keep tracking your nights.")
                        .font(.system(size: 17))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                Link(destination: AppStoreUpdate.productURL) {
                    Text("Update on the App Store")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.accent)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var firebase: FirebaseManager
    @EnvironmentObject var countryDetector: LocationCountryDetector
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var updateRequired = false

    var body: some View {
        Group {
            if appState.shouldShowAuth {
                AuthView()
            } else if firebase.isSignedIn && !appState.userProfile.onboardingComplete {
                // Signing out wipes the local profile, so the instant someone
                // signs back in a returning user is indistinguishable from a
                // new one. Wait for the cloud to say which, instead of asking
                // a long-standing customer for their weight again — and worse,
                // overwriting the real measurements when they answer.
                if appState.isRestoringCloudProfile {
                    RestoringProfileView()
                } else {
                    OnboardingView()
                }
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
                            case .guidedEvent(let id, let target):
                                ActiveEventView(eventId: id, guideTarget: target)
                            case .summary(let id):
                                SummaryView(eventId: id)
                            case .stories(let id):
                                StoriesView(eventId: id)
                            case .calendar:
                                CalendarView()
                            case .dashboard:
                                DashboardView()
                            case .challenges:
                                ChallengesView()
                            case .drinks:
                                DrinksView()
                            case .guidedDrinkCalories:
                                DrinksView(highlightsCalories: true)
                            case .profile:
                                ProfileView()
                            case .guidedProfile(let target):
                                ProfileView(guideTarget: target)
                            case .gettingStarted:
                                if let userID = appState.currentUserId {
                                    GettingStartedView(userID: userID)
                                        .id(userID)
                                }
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
                .onChange(of: appState.pendingEventRoute) { _, route in
                    guard let route else { return }
                    path.append(route)
                    appState.pendingEventRoute = nil
                }
            }
        }
        .preferredColorScheme(.dark)
        // Hosted here, outside the navigation stack, so a notice covers the
        // navigation bar rather than leaving it stranded above the backdrop.
        .noticeHost()
        // Above the notice host so nothing can sit on top of it. Re-checked
        // on every return to the foreground, so raising the minimum in
        // Firestore reaches people who leave the app open in the background.
        .overlay {
            if updateRequired { UpdateRequiredView() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let required = await RequiredUpdate.check()
            guard !Task.isCancelled else { return }
            updateRequired = required
        }
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
                // A sheet would present above the update overlay.
                guard !updateRequired, let r = countryDetector.result else { return nil }
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

