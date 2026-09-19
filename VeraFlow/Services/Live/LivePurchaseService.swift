import Foundation
import os
import StoreKit

/// One-time unlock with StoreKit 2 (SPEC §13): the non-consumable `veraflow.unlock.lifetime`,
/// verified through `Transaction.currentEntitlements`, kept current from `Transaction.updates`
/// (purchase, restore, Family Sharing, refund), plus the free-summary counter.
actor LivePurchaseService: PurchaseService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "purchases")

    private let counter: FreeSummaryCounter
    private var listeners: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var updatesTask: Task<Void, Never>?
    private var cachedProduct: Product?
    /// The entitlement as we last established it. `Transaction.currentEntitlements` can still be
    /// empty for a moment after a purchase is finished — on Jeremy's Mac the summary gate read
    /// "unlocked false" four times in a row straight after "unlock purchased", so the summary he
    /// had just paid for was skipped. A purchase writes the answer here instead of leaving every
    /// caller to race StoreKit; a refund arrives through `Transaction.updates` and rewrites it.
    private var cachedUnlocked: Bool?

    init(counter: FreeSummaryCounter = FreeSummaryCounter()) {
        self.counter = counter
    }

    // MARK: Entitlement

    func isUnlocked() async -> Bool {
        if let cachedUnlocked { return cachedUnlocked }
        let unlocked = await readEntitlement()
        cachedUnlocked = unlocked
        return unlocked
    }

    /// Asks StoreKit itself. Only the cache's own refresh points call this.
    private func readEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == ProductID.lifetimeUnlock,
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    func entitlementUpdates() async -> AsyncStream<Bool> {
        startListeningIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        listeners[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    private func startListeningIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    Self.log.info("transaction update for \(transaction.productID, privacy: .public)")
                }
                // A refund or a purchase made on another device: ask StoreKit again and keep it.
                await self.refreshEntitlement()
            }
        }
    }

    /// Re-reads the entitlement, stores it, and tells the listeners.
    private func refreshEntitlement() async {
        let unlocked = await readEntitlement()
        cachedUnlocked = unlocked
        broadcast(unlocked)
    }

    private func broadcast(_ unlocked: Bool) {
        for continuation in listeners.values {
            continuation.yield(unlocked)
        }
    }

    private func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    // MARK: Store

    func product() async throws -> UnlockProduct {
        let product = try await loadProduct()
        return UnlockProduct(id: product.id, displayName: product.displayName, displayPrice: product.displayPrice)
    }

    func purchase() async throws -> PurchaseOutcome {
        let product = try await loadProduct()
        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw PurchaseError.storeKitFailed(error.localizedDescription)
        }
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                // Verified and finished: the user is unlocked, whatever `currentEntitlements`
                // says for the next moment.
                cachedUnlocked = true
                broadcast(true)
                Self.log.info("unlock purchased")
                return .purchased
            case .unverified:
                throw PurchaseError.verificationFailed
            }
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws -> Bool {
        do {
            try await AppStore.sync()
        } catch {
            throw PurchaseError.storeKitFailed(error.localizedDescription)
        }
        let unlocked = await readEntitlement()
        cachedUnlocked = unlocked
        broadcast(unlocked)
        return unlocked
    }

    private func loadProduct() async throws -> Product {
        if let cachedProduct { return cachedProduct }
        let products: [Product]
        do {
            products = try await Product.products(for: [ProductID.lifetimeUnlock])
        } catch {
            throw PurchaseError.storeKitFailed(error.localizedDescription)
        }
        guard let product = products.first else { throw PurchaseError.productNotFound }
        cachedProduct = product
        return product
    }

    // MARK: Free tier

    func freeSummariesUsed() async -> Int {
        counter.value()
    }

    func recordFreeSummaryUsed() async {
        counter.increment()
    }
}
