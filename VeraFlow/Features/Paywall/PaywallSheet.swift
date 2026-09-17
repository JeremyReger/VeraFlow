import SwiftUI
import StoreKit

/// Monetization paywall for the one-time VeraFlow Lifetime Unlock (§13).
public struct PaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var product: Product? = nil
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String? = nil
    @State private var showSuccessToast = false
    @State private var capabilities: DeviceCapabilities? = nil
    
    private let purchaseService: PurchaseServiceProtocol
    private let capabilityService: CapabilityServiceProtocol
    
    public init(
        purchaseService: PurchaseServiceProtocol = StoreKitPurchaseService(),
        capabilityService: CapabilityServiceProtocol = CapabilityService()
    ) {
        self.purchaseService = purchaseService
        self.capabilityService = capabilityService
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero Icon & Badge
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.purple.opacity(0.2), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .padding(.top, 16)
                    
                    // Title & Subtitle
                    VStack(spacing: 8) {
                        Text("Unlock Lifetime Access")
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("One-time purchase • Zero recurring subscriptions • Family Sharing enabled")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    
                    // Feature List Card
                    VStack(alignment: .leading, spacing: 18) {
                        paywallFeatureRow(
                            icon: "brain.head.profile",
                            color: .purple,
                            title: "Unlimited Local AI Summaries",
                            subtitle: "Extract executive overviews and key points on-device using Apple Foundation Models."
                        )
                        
                        paywallFeatureRow(
                            icon: "list.bullet.clipboard.fill",
                            color: .blue,
                            title: "All 3 Real-World Templates",
                            subtitle: "General Meetings, Client Consulting Proposals, and Contractor Walk-Throughs."
                        )
                        
                        paywallFeatureRow(
                            icon: "doc.richtext.fill",
                            color: .orange,
                            title: "Full Document Exports",
                            subtitle: "Multi-page typographic PDFs with running headers and clean Markdown documents."
                        )
                        
                        paywallFeatureRow(
                            icon: "checklist.checked",
                            color: .green,
                            title: "Apple Reminders Integration",
                            subtitle: "Export action items with natural language due dates and audio timestamps."
                        )
                        
                        paywallFeatureRow(
                            icon: "person.2.fill",
                            color: .teal,
                            title: "Family Sharing Supported",
                            subtitle: "Share your lifetime unlock with everyone in your Apple Family group."
                        )
                    }
                    .padding(20)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    
                    // Device Capability Notice (§13, §15)
                    if capabilities?.hasAppleIntelligence == false {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Device Compatibility Notice")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("AI Summaries require an Apple Intelligence–capable iPhone (iPhone 15 Pro, iPhone 16+). Unlocking enables all export formats and unlocks unlimited future AI summaries.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                    }
                    
                    // Error Message Banner
                    if let err = purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Purchase Action Button
                    VStack(spacing: 12) {
                        let priceText = product?.displayPrice ?? "$19.99"
                        
                        Button {
                            performPurchase()
                        } label: {
                            HStack {
                                if isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Unlock Lifetime — \(priceText)")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(isPurchasing || isRestoring)
                        
                        Button {
                            performRestore()
                        } label: {
                            HStack {
                                if isRestoring {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text("Restore Purchases")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .disabled(isPurchasing || isRestoring)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                capabilities = await capabilityService.currentCapabilities()
                loadProduct()
            }
            .alert("Purchase Complete!", isPresented: $showSuccessToast) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thank you for supporting VeraFlow! You have unlocked lifetime access to all summaries, templates, and exports.")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func paywallFeatureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func loadProduct() {
        Task {
            if let storeKit = purchaseService as? StoreKitPurchaseService {
                product = try? await storeKit.fetchProduct()
            }
        }
    }
    
    private func performPurchase() {
        isPurchasing = true
        purchaseError = nil
        
        Task {
            do {
                let success = try await purchaseService.purchaseLifetimeUnlock()
                await MainActor.run {
                    isPurchasing = false
                    if success {
                        showSuccessToast = true
                    }
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    purchaseError = error.localizedDescription
                }
            }
        }
    }
    
    private func performRestore() {
        isRestoring = true
        purchaseError = nil
        
        Task {
            do {
                try await purchaseService.restorePurchases()
                let entitlement = await purchaseService.currentEntitlement()
                await MainActor.run {
                    isRestoring = false
                    if entitlement.isLifetimeUnlocked {
                        showSuccessToast = true
                    } else {
                        purchaseError = "No previous purchases were found for this Apple ID."
                    }
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    purchaseError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    PaywallSheet(purchaseService: FakePurchaseService())
}
