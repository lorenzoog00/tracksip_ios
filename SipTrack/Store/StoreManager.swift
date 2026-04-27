import StoreKit
import Foundation
import Combine

@MainActor
final class StoreManager: ObservableObject {

    // Configure these in App Store Connect to match:
    static let productIDs: Set<String> = [
        "com.lorenzoog.siptrack.pro.monthly",
        "com.lorenzoog.siptrack.pro.yearly",
        "com.lorenzoog.siptrack.pro.lifetime",
    ]

    @Published var products: [Product] = []
    @Published var isPro: Bool = false
    @Published var activePeriod: SubscriptionPeriod? = nil
    @Published var loadError: String? = nil

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshStatus()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Products

    func loadProducts() async {
        loadError = nil
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            if loaded.isEmpty {
                loadError = "No products returned. Check App Store Connect and bundle ID."
            }
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            loadError = error.localizedDescription
            print("StoreManager: failed to load products – \(error)")
        }
    }

    func retryLoadProducts() {
        Task { await loadProducts() }
    }

    func product(for period: SubscriptionPeriod) -> Product? {
        let id: String
        switch period {
        case .monthly:  id = "com.lorenzoog.siptrack.pro.monthly"
        case .yearly:   id = "com.lorenzoog.siptrack.pro.yearly"
        case .lifetime: id = "com.lorenzoog.siptrack.pro.lifetime"
        }
        return products.first { $0.id == id }
    }

    // MARK: - Purchasing

    enum PurchaseResult {
        case success, cancelled, pending, failed(Error)
    }

    func purchase(_ product: Product) async -> PurchaseResult {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshStatus()
                return .success
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error)
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshStatus()
    }

    // MARK: - Status

    func refreshStatus() async {
        var hasPro = false
        var detectedPeriod: SubscriptionPeriod? = nil

        // Race StoreKit against an 8-second timeout. Without proper IAP
        // entitlement on device, currentEntitlements can hang indefinitely.
        let checker = Task {
            for await result in Transaction.currentEntitlements {
                if let transaction = try? checkVerified(result) {
                    hasPro = true
                    detectedPeriod = period(for: transaction.productID)
                    break
                }
            }
        }
        let timer = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            checker.cancel()
        }
        await checker.value  // returns immediately when StoreKit responds OR after 8s timeout
        timer.cancel()       // stop the timer if StoreKit was fast

        isPro = hasPro
        activePeriod = detectedPeriod
    }

    private func period(for productID: String) -> SubscriptionPeriod? {
        switch productID {
        case "com.lorenzoog.siptrack.pro.monthly":  return .monthly
        case "com.lorenzoog.siptrack.pro.yearly":   return .yearly
        case "com.lorenzoog.siptrack.pro.lifetime": return .lifetime
        default: return nil
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
                await refreshStatus()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }
}
