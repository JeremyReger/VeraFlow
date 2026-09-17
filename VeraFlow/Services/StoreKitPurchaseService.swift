import Foundation
import StoreKit

/// Production StoreKit 2 purchase service managing non-consumable lifetime unlock and Keychain-backed free quotas (§13).
public final class StoreKitPurchaseService: PurchaseServiceProtocol, @unchecked Sendable {
    
    public static let primaryProductID = "veraflow.unlock.lifetime"
    public static let fallbackProductID = "riffle.unlock.lifetime"
    public static let allProductIDs = [primaryProductID, fallbackProductID]
    
    private let keychain: KeychainStorage
    private let freeUsedKeychainKey = "veraflow.free_summaries_used"
    private var updateListenerTask: Task<Void, Never>? = nil
    
    public init(keychain: KeychainStorage = KeychainStorage()) {
        self.keychain = keychain
        self.updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Entitlements (§13)
    
    public func currentEntitlement() async -> UserEntitlementState {
        let isUnlocked = await checkLifetimeEntitlement()
        let freeUsed = getFreeSummariesUsed()
        let remaining = max(0, AppConstants.freeSummaryLimit - freeUsed)
        
        return UserEntitlementState(
            isLifetimeUnlocked: isUnlocked,
            freeSummariesUsed: freeUsed,
            freeSummariesRemaining: remaining
        )
    }
    
    public func canGenerateSummary() async -> Bool {
        let isUnlocked = await checkLifetimeEntitlement()
        if isUnlocked { return true }
        let freeUsed = getFreeSummariesUsed()
        return freeUsed < AppConstants.freeSummaryLimit
    }
    
    public func recordSummaryGeneration() async {
        let isUnlocked = await checkLifetimeEntitlement()
        if !isUnlocked {
            let current = getFreeSummariesUsed()
            setFreeSummariesUsed(current + 1)
        }
    }
    
    // MARK: - StoreKit 2 Operations (§13)
    
    public func fetchProduct() async throws -> Product? {
        let products = try await Product.products(for: Self.allProductIDs)
        // Prefer primary, fallback to demo/alpha
        return products.first(where: { $0.id == Self.primaryProductID }) ?? products.first
    }
    
    public func purchaseLifetimeUnlock() async throws -> Bool {
        guard let product = try await fetchProduct() else {
            throw PurchaseError.productNotFound
        }
        
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return true
            case .unverified(_, let error):
                throw PurchaseError.verificationFailed(error.localizedDescription)
            }
        case .userCancelled:
            return false
        case .pending:
            return false
        @unknown default:
            return false
        }
    }
    
    public func restorePurchases() async throws {
        try await AppStore.sync()
    }
    
    // MARK: - Internal Verification
    
    private func checkLifetimeEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if Self.allProductIDs.contains(transaction.productID) && transaction.revocationDate == nil {
                    return true
                }
            }
        }
        return false
    }
    
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }
    
    // MARK: - Keychain Quota Management (§13)
    
    private func getFreeSummariesUsed() -> Int {
        if let count = keychain.integer(forKey: freeUsedKeychainKey) {
            return count
        }
        // Fallback to UserDefaults if Keychain is clean
        return UserDefaults.standard.integer(forKey: freeUsedKeychainKey)
    }
    
    private func setFreeSummariesUsed(_ count: Int) {
        keychain.set(count, forKey: freeUsedKeychainKey)
        UserDefaults.standard.set(count, forKey: freeUsedKeychainKey)
    }
}

public enum PurchaseError: LocalizedError, Sendable {
    case productNotFound
    case verificationFailed(String)
    case transactionFailed
    
    public var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Unable to retrieve the unlock product from the App Store. Please check your connection or try again later."
        case .verificationFailed(let reason):
            return "App Store transaction verification failed: \(reason)"
        case .transactionFailed:
            return "The transaction could not be completed."
        }
    }
}
