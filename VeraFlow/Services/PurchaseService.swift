import Foundation

/// Product identifiers (SPEC §13.1).
enum ProductID {
    static let lifetimeUnlock = "veraflow.unlock.lifetime"
}

/// Free-tier limits (SPEC §13.2).
enum FreeTier {
    static let summaryLimit = 3
}

enum PurchaseOutcome: Sendable, Equatable {
    case purchased
    case pending
    case cancelled
}

enum PurchaseError: Error, Equatable {
    case productNotFound
    case verificationFailed
    case storeKitFailed(String)
}

/// Localized product info for the paywall.
struct UnlockProduct: Sendable, Equatable {
    var id: String
    var displayName: String
    var displayPrice: String
}

/// One-time unlock via StoreKit 2 plus the free-summary counter (SPEC §13). Implemented for real in M8.
protocol PurchaseService: Sendable {
    func isUnlocked() async -> Bool
    func product() async throws -> UnlockProduct
    func purchase() async throws -> PurchaseOutcome
    /// Restores purchases; returns whether the unlock is now active.
    func restore() async throws -> Bool
    /// Emits the entitlement state whenever it changes (purchase, restore, refund).
    func entitlementUpdates() async -> AsyncStream<Bool>
    /// How many free summaries have been used. Stored in Keychain + UserDefaults (SPEC §13.2).
    func freeSummariesUsed() async -> Int
    func recordFreeSummaryUsed() async
}

extension PurchaseService {
    /// Whether the user may generate another summary right now.
    func canGenerateSummary() async -> Bool {
        if await isUnlocked() { return true }
        return await freeSummariesUsed() < FreeTier.summaryLimit
    }
}

actor FakePurchaseService: PurchaseService {
    private(set) var unlocked: Bool
    private(set) var freeUsed: Int
    var purchaseOutcome: PurchaseOutcome = .purchased
    var errorToThrow: PurchaseError?
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(unlocked: Bool = false, freeSummariesUsed: Int = 0) {
        self.unlocked = unlocked
        self.freeUsed = freeSummariesUsed
    }

    func isUnlocked() async -> Bool { unlocked }

    func product() async throws -> UnlockProduct {
        if let errorToThrow { throw errorToThrow }
        return UnlockProduct(id: ProductID.lifetimeUnlock, displayName: "VeraFlow Unlock", displayPrice: "$24.99")
    }

    func purchase() async throws -> PurchaseOutcome {
        if let errorToThrow { throw errorToThrow }
        if purchaseOutcome == .purchased {
            setUnlocked(true)
        }
        return purchaseOutcome
    }

    func restore() async throws -> Bool {
        if let errorToThrow { throw errorToThrow }
        return unlocked
    }

    func entitlementUpdates() async -> AsyncStream<Bool> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    func freeSummariesUsed() async -> Int { freeUsed }

    func recordFreeSummaryUsed() async {
        freeUsed += 1
    }

    /// Test control: flips the entitlement (e.g. simulate a refund) and notifies listeners.
    func setUnlocked(_ value: Bool) {
        unlocked = value
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
