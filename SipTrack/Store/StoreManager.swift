import StoreKit
import Foundation

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

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { await listenForTransactions() }
        Task {
            await loadProducts()
            await refreshStatus()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Products

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            print("StoreManager: failed to load products – \(error)")
        }
    }

    func product(for period: SubscriptionPeriod) -> Product? {
        let id: String
        switch period {
        case .monthly:  id = "com.siptrack.pro.monthly"
        case .yearly:   id = "com.siptrack.pro.yearly"
        case .lifetime: id = "com.siptrack.pro.lifetime"
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
        for await result in Transaction.currentEntitlements {
            if (try? checkVerified(result)) != nil {
                hasPro = true
                break
            }
        }
        isPro = hasPro
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
