import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct SipTrackApp: App {

    @StateObject private var store: StoreManager
    @StateObject private var appState: AppState
    @StateObject private var adManager = AdManager.shared
    @StateObject private var firebase  = FirebaseManager.shared
    @StateObject private var countryDetector = LocationCountryDetector()

    init() {
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
                    AdManager.shared.showAppOpenAdIfReady(isPro: appState.isPro)
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
    }
}
