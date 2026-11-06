import SwiftUI
import FirebaseCore
import FirebaseAppCheck
import GoogleSignIn
import BackgroundTasks

@main
struct SipTrackApp: App {

    @StateObject private var store: StoreManager
    @StateObject private var appState: AppState
    @StateObject private var adManager = AdManager.shared
    @StateObject private var firebase  = FirebaseManager.shared
    @StateObject private var countryDetector = LocationCountryDetector()

    init() {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(ProductionAppCheckProviderFactory())
        #endif
        FirebaseApp.configure()
        let s = StoreManager()
        let state = AppState(store: s)
        _store    = StateObject(wrappedValue: s)
        _appState = StateObject(wrappedValue: state)
        WatchBridge.shared.appState = state
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
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
                    Task {
                        await store.refreshStatus()
                        appState.syncSubscriptionFromStore()
                        await ConsentManager.shared.refreshOnForeground()
                        AdManager.shared.showAppOpenAdIfReady(isPro: appState.isPro)
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
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    guard url.scheme == "siptrack",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let eventId = components.queryItems?.first(where: { $0.name == "event" })?.value
                    else { return }

                    switch url.host {
                    case "drink":
                        if let typeId = components.queryItems?.first(where: { $0.name == "type" })?.value {
                            appState.addDrink(eventId: eventId, drinkTypeId: typeId)
                        }
                    case "water":
                        appState.addWater(eventId: eventId)
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
