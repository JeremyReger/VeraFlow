import Foundation
import Testing
@testable import VeraFlow

struct FreeSummaryCounterTests {
    @Test("The count lives in the Keychain and UserDefaults; the larger value wins")
    func counter() throws {
        let suite = "FreeSummaryCounterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let counter = FreeSummaryCounter(service: "com.jeremyreger.veraflow.tests", account: UUID().uuidString, defaults: defaults)
        defer {
            counter.reset()
            defaults.removePersistentDomain(forName: suite)
        }

        #expect(counter.value() == 0)
        counter.increment()
        counter.increment()
        #expect(counter.value() == 2)

        // Wiping UserDefaults (as a reinstall would) doesn't reset the count.
        defaults.removeObject(forKey: counter.defaultsKey)
        #expect(counter.value() == 2)

        // Neither does lowering one of the stores by hand.
        defaults.set(0, forKey: counter.defaultsKey)
        #expect(counter.value() == 2)
        counter.set(5)
        #expect(counter.value() == 5)
        counter.reset()
        #expect(counter.value() == 0)
    }
}

@MainActor
struct PaywallModelTests {
    @Test("Purchase unlocks; cancel and pending don't; errors become messages")
    func purchase() async {
        let purchases = FakePurchaseService()
        let model = PaywallModel(purchases: purchases)
        await model.load()
        #expect(model.product?.displayPrice == "$24.99")

        await purchases.setPurchaseOutcome(.cancelled)
        await model.purchase()
        #expect(!model.didUnlock)
        #expect(model.message == nil)

        await purchases.setPurchaseOutcome(.pending)
        await model.purchase()
        #expect(!model.didUnlock)
        #expect(model.message?.contains("Ask to Buy") == true)

        await purchases.setPurchaseOutcome(.purchased)
        await model.purchase()
        #expect(model.didUnlock)
        #expect(await purchases.isUnlocked())

        await purchases.setError(.productNotFound)
        let broken = PaywallModel(purchases: purchases)
        await broken.load()
        #expect(broken.product == nil)
        #expect(broken.message?.contains("isn't available") == true)
    }

    @Test("Restore reports whether a purchase was found")
    func restore() async {
        let purchases = FakePurchaseService(unlocked: false)
        let model = PaywallModel(purchases: purchases)
        await model.restore()
        #expect(!model.didUnlock)
        #expect(model.message?.contains("No previous purchase") == true)

        await purchases.setUnlocked(true)
        await model.restore()
        #expect(model.didUnlock)
    }
}

struct ExportGateTests {
    @Test("Free tier allows only the plain-text copies; unlocked allows everything")
    func gate() {
        #expect(ExportGate.isAllowed(.copySummary, unlocked: false))
        #expect(ExportGate.isAllowed(.copyActionItems, unlocked: false))
        #expect(!ExportGate.isAllowed(.file(.markdown), unlocked: false))
        #expect(!ExportGate.isAllowed(.file(.audio), unlocked: false))
        #expect(!ExportGate.isAllowed(.email, unlocked: false))
        #expect(!ExportGate.isAllowed(.reminders, unlocked: false))
        #expect(ExportGate.isAllowed(.file(.pdf), unlocked: true))
        #expect(ExportGate.isAllowed(.reminders, unlocked: true))
    }
}
