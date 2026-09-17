import Foundation

public struct UserEntitlementState: Sendable {
    public var isLifetimeUnlocked: Bool
    public var freeSummariesUsed: Int
    public var freeSummariesRemaining: Int
    
    public init(isLifetimeUnlocked: Bool = false, freeSummariesUsed: Int = 0, freeSummariesRemaining: Int = 3) {
        self.isLifetimeUnlocked = isLifetimeUnlocked
        self.freeSummariesUsed = freeSummariesUsed
        self.freeSummariesRemaining = freeSummariesRemaining
    }
}

public protocol PurchaseServiceProtocol: Sendable {
    func currentEntitlement() async -> UserEntitlementState
    func purchaseLifetimeUnlock() async throws -> Bool
    func restorePurchases() async throws
    func canGenerateSummary() async -> Bool
    func recordSummaryGeneration() async
}
