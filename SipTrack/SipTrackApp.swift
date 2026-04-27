import SwiftUI

@main
struct SipTrackApp: App {

    @StateObject private var store: StoreManager
    @StateObject private var appState: AppState
    @StateObject private var adManager = AdManager.shared
    @StateObject private var supabase  = SupabaseManager.shared

    init() {
        let s = StoreManager()
        _store    = StateObject(wrappedValue: s)
        _appState = StateObject(wrappedValue: AppState(store: s))
        AdManager.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(store)
                .environmentObject(adManager)
                .environmentObject(supabase)
                .preferredColorScheme(.dark)
                .task {
                    // Start Supabase immediately — never block on StoreKit
                    supabase.startListening()
                    // Run store + ads in parallel, independently
                    Task {
                        await store.refreshStatus()
                        appState.syncSubscriptionFromStore()
                    }
                    Task {
                        await AdManager.shared.loadAppOpenAd()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    AdManager.shared.showAppOpenAdIfReady(isPro: appState.isPro)
                }
        }
    }
}
