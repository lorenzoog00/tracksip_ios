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

enum AppTab: Hashable { case home, social }

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
    @EnvironmentObject var friends: FriendsStore
    /// Social is built on first visit, so its listeners don't start for people who never open it.
    @State private var socialVisited = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var updateRequired = false
    /// A lock-screen camera tap waiting for the app to finish coming to the front.
    @State private var pendingCamera: CameraRequest?

    /// True when the tabs are on screen, not sign-in, onboarding or the
    /// update-required wall.
    private var showsTabs: Bool {
        !appState.shouldShowAuth
            && !(firebase.isSignedIn && !appState.userProfile.onboardingComplete)
            && !updateRequired
    }

    /// The lock-screen camera button. The request moves to `pendingCamera` and is
    /// served by presentPendingCamera, which waits for the app to be ready instead of
    /// dropping it.
    ///
    /// The camera is presented from here, not by the night screen. It used to push a
    /// fresh night screen that opened its own camera, and when that night screen was
    /// already on top SwiftUI kept the existing one, so the camera never opened.
    private func handleCameraRequest() {
        guard let request = appState.cameraRequest else { return }
        appState.cameraRequest = nil
        pendingCamera = request
    }

    /// Opens the camera for a lock-screen tap. Every early version of this lost the
    /// tap somewhere, so each step now waits rather than gives up:
    ///  - A cold launch (iOS often kills the app while the phone is locked) starts
    ///    signed out for a moment, and that flip resets the navigation stack; wait
    ///    until sign-in has settled and the tabs are on screen.
    ///  - The tap arrives before unlock finishes; wait for the scene to be active.
    ///  - A presentation refused mid-transition fails silently; check the camera is
    ///    really in a window afterwards, and try again if not.
    /// Any running night will do: the card's id can trail the app's after a sync.
    private func presentPendingCamera() async {
        guard let request = pendingCamera else { return }
        // Cleared only at the end: changing pendingCamera restarts this task, which
        // would cancel the sleeps below and spend every retry at once.
        defer { if pendingCamera?.id == request.id { pendingCamera = nil } }

        // Up to 30 s for the app to be ready: the tap lands on the Lock Screen, and
        // Face ID or the passcode comes before the app is active.
        //
        // Not `scenePhase`: this task holds the copy of the view it started with, and
        // an @Environment value in that copy never changes. A tap that arrived while
        // the app was in the background saw "background" for the whole wait, gave up,
        // and only a second tap (app already active) opened the camera.
        for _ in 0..<150 {
            if Task.isCancelled { return }
            if Self.appIsActive, showsTabs, firebase.isSignedIn,
               !appState.isRestoringCloudProfile { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard !Task.isCancelled, Self.appIsActive, showsTabs else { return }

        guard let night = appState.activeEvent else {
            NoticeCenter.shared.show(Notice(
                icon: "moon.zzz.fill",
                title: "This night has ended",
                message: "Photos can only be added while the night is running.",
                actions: [NoticeAction("OK")]
            ))
            return
        }

        // The night screen underneath, so closing the camera lands there.
        appState.selectedTab = .home
        var nightOnly = NavigationPath()
        nightOnly.append(Route.event(night.id))
        if path != nightOnly { path = nightOnly }
        try? await Task.sleep(for: .milliseconds(450))

        // Up to about 6 s of attempts.
        for _ in 0..<12 {
            if Task.isCancelled || LockScreenCamera.isShowing { return }
            let presented = LockScreenCamera.present(eventId: night.id) {
                appState.nightPhotoRevision += 1
                Haptics.shared.play(.success)
            }
            try? await Task.sleep(for: .milliseconds(presented ? 700 : 300))
        }
    }

    /// Read live from UIKit, unlike `scenePhase` inside a running task.
    private static var appIsActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// A friend link. Dropped when the tabs are not showing (signed out, onboarding), like
    /// the camera request; otherwise left set for SocialRootView to present and clear.
    private func handleFriendLink() {
        guard appState.pendingFriendLink != nil else { return }
        // On a cold launch (a tapped push or link) the stored session is restored a
        // moment after the first frame. Wait for it rather than drop the link; the
        // sign-in change below calls this again.
        if !firebase.isSignedIn && appState.currentUserId != nil { return }
        guard showsTabs, firebase.isSignedIn else {
            appState.pendingFriendLink = nil
            return
        }
        appState.selectedTab = .social
    }

    /// A tapped reaction/comment push. Same rules as a friend link: wait for a
    /// cold-launch session restore, drop it when the tabs are not showing, otherwise
    /// switch to Social, whose feed opens the sheet and clears this.
    private func handlePendingThread() {
        guard appState.pendingThread != nil else { return }
        if !firebase.isSignedIn && appState.currentUserId != nil { return }
        guard showsTabs, firebase.isSignedIn else {
            appState.pendingThread = nil
            return
        }
        appState.selectedTab = .social
    }

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
                // Home and Social stay alive side by side, so switching keeps each one's
                // place. No tab bar: the switch sits at the top of both root screens
                // (AppTabSwitcher), and pushed screens have the whole height.
                ZStack {
                    NavigationStack(path: $path) {
                        HomeView()
                            .task {
                                if appState.shouldAttemptCountryDetection {
                                    countryDetector.requestOnce()
                                }
                            }
                            .navigationDestination(for: Route.self) { route in
                                Group {
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
                    }
                    .onChange(of: appState.pendingSummaryEventId) { _, newValue in
                        guard let eventId = newValue else { return }
                        appState.selectedTab = .home
                        if !path.isEmpty { path.removeLast() }
                        path.append(Route.summary(eventId))
                        appState.pendingSummaryEventId = nil
                    }
                    .onChange(of: appState.pendingEventRoute) { _, route in
                        guard let route else { return }
                        appState.selectedTab = .home
                        path.append(route)
                        appState.pendingEventRoute = nil
                    }
                    .opacity(appState.selectedTab == .home ? 1 : 0)
                    .allowsHitTesting(appState.selectedTab == .home)
                    .accessibilityHidden(appState.selectedTab != .home)

                    if socialVisited || appState.selectedTab == .social {
                        SocialRootView()
                            .opacity(appState.selectedTab == .social ? 1 : 0)
                            .allowsHitTesting(appState.selectedTab == .social)
                            .accessibilityHidden(appState.selectedTab != .social)
                            .onAppear { socialVisited = true }
                    }
                }
                // The morning check-in (a tapped morning notification, the Home
                // card or the summary's "Check in"). The binding is read on
                // every render rather than watched with onChange, so a cold
                // launch from the notification, which sets `pendingCheckIn`
                // before this view exists, still presents it once the stored
                // session is restored. It never covers the update wall.
                .sheet(item: Binding<PendingCheckIn?>(
                    get: {
                        guard firebase.isSignedIn, !updateRequired else { return nil }
                        return appState.pendingCheckIn
                    },
                    set: { appState.pendingCheckIn = $0 }
                )) { pending in
                    MorningCheckInSheet(pending: pending,
                                        opensOnPlan: appState.morningPlans[pending.eventId] != nil)
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
        .onChange(of: appState.cameraRequest) { _, _ in handleCameraRequest() }
        .task(id: pendingCamera?.id) { await presentPendingCamera() }
        .onAppear {
            handleCameraRequest()
            handleFriendLink()
            handlePendingThread()
        }
        .onChange(of: appState.pendingFriendLink) { _, _ in handleFriendLink() }
        .onChange(of: appState.pendingThread) { _, _ in handlePendingThread() }
        .onChange(of: showsTabs) { _, showing in
            if !showing {
                appState.pendingFriendLink = nil
                appState.pendingThread = nil
            }
        }
        .onChange(of: appState.pendingOpenFriends) { _, open in
            if open { appState.selectedTab = .social }
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
            if signedIn {
                handleFriendLink()
                handlePendingThread()
            }
            if !signedIn {
                appState.selectedTab = .home
                appState.pendingFriendLink = nil
                appState.pendingThread = nil
            }
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

