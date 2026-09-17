import Testing
import Foundation
@testable import VeraFlow

@Suite("StoreKit 2 & Monetization Tests (§13, §16 M8)")
struct PurchaseTests {
    
    @Test("KeychainStorage reliably writes, reads, updates, and removes integers (§13)")
    func testKeychainStorage() {
        let keychain = KeychainStorage(service: "com.veraflow.test.keychain.\(UUID().uuidString)")
        let testKey = "test.quota.key"
        
        // 1. Initial read should be nil
        #expect(keychain.integer(forKey: testKey) == nil)
        
        // 2. Set value
        keychain.set(2, forKey: testKey)
        #expect(keychain.integer(forKey: testKey) == 2)
        
        // 3. Update value
        keychain.set(3, forKey: testKey)
        #expect(keychain.integer(forKey: testKey) == 3)
        
        // 4. Remove value
        keychain.remove(forKey: testKey)
        #expect(keychain.integer(forKey: testKey) == nil)
    }
    
    @Test("PurchaseService tracks free tier quota of 3 summaries accurately (§13)")
    func testFreeTierQuota() async {
        let fake = FakePurchaseService(isUnlocked: false, freeUsed: 0)
        
        // Initial state
        var ent = await fake.currentEntitlement()
        #expect(!ent.isLifetimeUnlocked)
        #expect(ent.freeSummariesUsed == 0)
        #expect(ent.freeSummariesRemaining == 3)
        #expect(await fake.canGenerateSummary() == true)
        
        // Use 1 summary
        await fake.recordSummaryGeneration()
        ent = await fake.currentEntitlement()
        #expect(ent.freeSummariesUsed == 1)
        #expect(ent.freeSummariesRemaining == 2)
        #expect(await fake.canGenerateSummary() == true)
        
        // Use 2 more summaries (total 3)
        await fake.recordSummaryGeneration()
        await fake.recordSummaryGeneration()
        ent = await fake.currentEntitlement()
        #expect(ent.freeSummariesUsed == 3)
        #expect(ent.freeSummariesRemaining == 0)
        #expect(await fake.canGenerateSummary() == false)
    }
    
    @Test("Lifetime unlock bypasses quota and unlocks unlimited summaries (§13)")
    func testLifetimeUnlock() async throws {
        let fake = FakePurchaseService(isUnlocked: false, freeUsed: 3)
        
        // Locked with quota exhausted
        #expect(await fake.canGenerateSummary() == false)
        
        // Perform purchase
        let success = try await fake.purchaseLifetimeUnlock()
        #expect(success)
        
        let ent = await fake.currentEntitlement()
        #expect(ent.isLifetimeUnlocked)
        #expect(await fake.canGenerateSummary() == true)
    }
    
    @Test("Restore purchases activates lifetime unlock (§13)")
    func testRestorePurchases() async throws {
        let fake = FakePurchaseService(isUnlocked: false, freeUsed: 3)
        #expect(await fake.canGenerateSummary() == false)
        
        try await fake.restorePurchases()
        let ent = await fake.currentEntitlement()
        #expect(ent.isLifetimeUnlocked)
        #expect(await fake.canGenerateSummary() == true)
    }
    
    @Test("StoreKitPurchaseService product ID alignment with specifications (§13)")
    func testStoreKitProductIDs() {
        #expect(StoreKitPurchaseService.primaryProductID == "veraflow.unlock.lifetime")
        #expect(StoreKitPurchaseService.fallbackProductID == "riffle.unlock.lifetime")
        #expect(StoreKitPurchaseService.allProductIDs.count == 2)
        #expect(StoreKitPurchaseService.allProductIDs.contains("veraflow.unlock.lifetime"))
        #expect(StoreKitPurchaseService.allProductIDs.contains("riffle.unlock.lifetime"))
    }
}
