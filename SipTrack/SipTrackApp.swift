import SwiftUI

@main
struct SipTrackApp: App {

    @StateObject private var store    = StoreManager()
    @StateObject private var appState: AppState

    init() {
        let s = StoreManager()
        _store    = StateObject(wrappedValue: s)
        _appState = StateObject(wrappedValue: AppState(store: s))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task {
                    // Keep subscription status in sync with StoreKit
                    await store.refreshStatus()
                    appState.syncSubscriptionFromStore()
                }
        }
    }
}
