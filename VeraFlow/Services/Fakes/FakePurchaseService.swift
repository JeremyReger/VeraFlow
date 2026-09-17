import Foundation

public final class FakePurchaseService: PurchaseServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var isUnlocked: Bool
    private var freeUsed: Int
    
    public init(isUnlocked: Bool = false, freeUsed: Int = 0) {
        self.isUnlocked = isUnlocked
        self.freeUsed = freeUsed
    }
    
    public func currentEntitlement() async -> UserEntitlementState {
        lock.withLock {
            UserEntitlementState(
                isLifetimeUnlocked: isUnlocked,
                freeSummariesUsed: freeUsed,
                freeSummariesRemaining: max(0, AppConstants.freeSummaryLimit - freeUsed)
            )
        }
    }
    
    public func purchaseLifetimeUnlock() async throws -> Bool {
        lock.withLock {
            isUnlocked = true
            return true
        }
    }
    
    public func restorePurchases() async throws {
        lock.withLock {
            isUnlocked = true
        }
    }
    
    public func canGenerateSummary() async -> Bool {
        lock.withLock {
            isUnlocked || freeUsed < AppConstants.freeSummaryLimit
        }
    }
    
    public func recordSummaryGeneration() async {
        lock.withLock {
            freeUsed += 1
        }
    }
}
