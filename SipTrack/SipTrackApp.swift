import SwiftUI
import FirebaseCore
import FirebaseAppCheck
import FirebaseAuth
import GoogleSignIn
import BackgroundTasks

@main
struct SipTrackApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: StoreManager
    @StateObject private var appState: AppState
    @StateObject private var friends: FriendsStore
    @StateObject private var adManager = AdManager.shared
    @StateObject private var firebase  = FirebaseManager.shared
    @StateObject private var countryDetector = LocationCountryDetector()

    /// Nothing here may touch Firebase (see `FirebaseSetup`). The autoclosures
    /// only run when the scene first reads them, after the app delegate's
    /// `didFinishLaunching` has configured Firebase and built `AppServices`.
    init() {
        _store    = StateObject(wrappedValue: AppServices.shared.store)
        _appState = StateObject(wrappedValue: AppServices.shared.appState)
        _friends  = StateObject(wrappedValue: AppServices.shared.friends)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(friends)
                .environmentObject(store)
                .environmentObject(adManager)
                .environmentObject(firebase)
                .environmentObject(countryDetector)
                .preferredColorScheme(.dark)
                .task {
                    firebase.startListening()
                    Task {
                        await store.refreshStatus()
                        appState.syncSubscriptionFromStore()
                    }
                    Task {
                        await ConsentManager.shared.gatherConsentAndInitializeAds()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Haptics.shared.prepare()
                    appState.refreshWaterReminder()
                    appState.refreshLiveState()
                    appState.refreshOnForeground()
                    Task {
                        await store.refreshStatus()
                        appState.syncSubscriptionFromStore()
                        await ConsentManager.shared.refreshOnForeground()
                        if firebase.isSignedIn {
                            AdManager.shared.showAppOpenAdIfReady(isPro: appState.isPro)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    Haptics.shared.stop()
                    appState.refreshLiveState()
                    LiveActivityRefresh.schedule(active: appState.activeEvent != nil)
                }
                .onChange(of: store.isPro) { _, _ in
                    appState.syncSubscriptionFromStore()
                }
                .onOpenURL { url in
                    // Phone auth's reCAPTCHA fallback returns through a URL.
                    if Auth.auth().canHandle(url) { return }
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    if let username = FriendLink.username(from: url) {
                        // The app-open ad would present on the same root as the sheet.
                        AdManager.shared.suppressAppOpenAd(for: 30)
                        appState.pendingFriendLink = username
                        return
                    }
                    guard url.scheme == "siptrack",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let eventId = components.queryItems?.first(where: { $0.name == "event" })?.value
                    else { return }

                    // Logging links only count for the night that is running: any app
                    // can open a siptrack:// URL, and an old or guessed id must not log.
                    let mayLog = LogDeepLink.accepts(eventId: eventId, activeEventId: appState.activeEvent?.id)
                    switch url.host {
                    case "drink":
                        if mayLog, let typeId = components.queryItems?.first(where: { $0.name == "type" })?.value {
                            appState.addDrink(eventId: eventId, drinkTypeId: typeId)
                        }
                    case "water":
                        if mayLog { appState.addWater(eventId: eventId) }
                    case "camera":
                        // RootView checks the night is still running. The app-open
                        // ad would present on the same root and knock the camera out.
                        AdManager.shared.suppressAppOpenAd(for: 30)
                        appState.cameraRequest = CameraRequest(eventId: eventId)
                    default:
                        break
                    }
                }
        }
        // iOS suspends the app when the phone locks, so the 10 s tick stops and the
        // lock-screen BAC freezes. Background app refresh is the only way to run
        // without a push server; iOS decides when (often every 15-30 min, less on
        // low battery), so this narrows the gap rather than closing it.
        .backgroundTask(.appRefresh(LiveActivityRefresh.identifier)) {
            await MainActor.run {
                appState.refreshLiveState()
                LiveActivityRefresh.schedule(active: appState.activeEvent != nil)
            }
        }
    }
}

/// `siptrack://drink` and `siptrack://water` (widgets, Live Activity) log only into
/// the active night.
enum LogDeepLink {
    nonisolated static func accepts(eventId: String, activeEventId: String?) -> Bool {
        !eventId.isEmpty && eventId == activeEventId
    }
}

extension LiveActivityActions {
    /// Leaves "Red Wine added" on the card for a few seconds, then clears it.
    /// iOS keeps the background launch alive while an intent runs, so waiting
    /// here is what lets the message go away without the app being opened.
    static func showActionBriefly() async {
        try? await Task.sleep(for: .seconds(5))
        await LiveActivityManager.shared.clearAction()
    }
}

enum LiveActivityRefresh {
    static let identifier = "com.lorenzoog.siptrack.liveactivity.refresh"

    static func schedule(active: Bool) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard active else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

private final class ProductionAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

/// Firebase is configured from the app delegate's `didFinishLaunching`, never in
/// `App.init`. Firebase Auth is created the moment Firebase is configured and
/// sets up its phone-auth managers right then; from `App.init` on iOS 26 they
/// stayed nil, and the first APNs token handed to Auth crashed every launch of
/// TestFlight 1.0.9 (firebase-ios-sdk #16273: configure in didFinishLaunching).
enum FirebaseSetup {
    /// A flag, not `FirebaseApp.app() == nil`: asking Firebase before it is
    /// configured logs an error on every cold launch.
    private static var configured = false

    static func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
        #endif
        FirebaseApp.configure()
    }
}

/// The app's long-lived stores. Built by the app delegate right after Firebase is
/// configured (they read `FirebaseManager.shared`), and read by `SipTrackApp`.
final class AppServices {
    static let shared = AppServices()

    let store: StoreManager
    let appState: AppState
    let friends: FriendsStore

    private init() {
        // Normally a no-op: didFinishLaunching configured Firebase already. Kept so
        // nothing can reach the stores before Firebase exists.
        FirebaseSetup.configureIfNeeded()
        let s = StoreManager()
        let state = AppState(store: s)
        store = s
        appState = state
        friends = FriendsStore(appState: state)
        WatchBridge.shared.appState = state
        PushRegistration.onOpen = { [weak state] route in
            guard let state else { return }
            switch route {
            case .friends:
                state.pendingOpenFriends = true
            case .add(let username):
                // The same add sheet a shared profile link opens.
                AdManager.shared.suppressAppOpenAd(for: 30)
                state.pendingFriendLink = username
            case .social:
                state.selectedTab = .social
            case .thread(let owner, let startedAt):
                // RootView switches to Social (after a cold-launch sign-in restore) and
                // the feed opens the comment sheet.
                AdManager.shared.suppressAppOpenAd(for: 30)
                state.pendingThread = NightKey(owner: owner, startedAt: startedAt)
            }
        }
        // Lock-screen buttons. iOS runs these in a background launch and ends it
        // when the intent returns, so each one waits for the lock screen and the
        // push server to hear about the change first.
        LiveActivityActions.openCamera = { [weak state] eventId in
            // The app-open ad would present on the same root and knock the camera out.
            AdManager.shared.suppressAppOpenAd(for: 30)
            state?.cameraRequest = CameraRequest(eventId: eventId)
        }
        LiveActivityActions.addDrink = { [weak state] eventId, drinkTypeId in
            guard let state else { return }
            let name = state.allDrinkTypes.first { $0.id == drinkTypeId }?.name ?? "Drink"
            LiveActivityManager.shared.alertOnNextUpdate("\(name) added")
            state.addDrink(eventId: eventId, drinkTypeId: drinkTypeId)
            await LiveActivityManager.shared.flush()
            await LiveActivityActions.showActionBriefly()
        }
        LiveActivityActions.addWater = { [weak state] eventId in
            guard let state else { return }
            LiveActivityManager.shared.alertOnNextUpdate("Water added")
            state.addWater(eventId: eventId)
            await LiveActivityManager.shared.flush()
            await LiveActivityActions.showActionBriefly()
        }
    }
}
