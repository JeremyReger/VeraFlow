import SwiftUI

/// Drives the paywall: product info, purchase, restore (SPEC §13.3).
@Observable
@MainActor
final class PaywallModel {
    private(set) var product: UnlockProduct?
    private(set) var isWorking = false
    private(set) var message: String?
    private(set) var didUnlock = false

    private let purchases: any PurchaseService

    init(purchases: any PurchaseService) {
        self.purchases = purchases
    }

    func load() async {
        do {
            product = try await purchases.product()
        } catch {
            message = Self.message(for: error)
        }
    }

    func purchase() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await purchases.purchase() {
            case .purchased:
                didUnlock = true
                message = nil
            case .pending:
                message = "Your purchase is waiting for approval (Ask to Buy). VeraFlow unlocks as soon as it's approved."
            case .cancelled:
                break
            }
        } catch {
            message = Self.message(for: error)
        }
    }

    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if try await purchases.restore() {
                didUnlock = true
                message = nil
            } else {
                message = "No previous purchase was found for this Apple Account."
            }
        } catch {
            message = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        if let error = error as? PurchaseError {
            switch error {
            case .productNotFound: return "The unlock isn't available in the App Store right now. Please try again later."
            case .verificationFailed: return "The App Store couldn't verify the purchase. Please try again."
            case .storeKitFailed(let detail): return "The App Store reported a problem: \(detail)"
            }
        }
        return error.localizedDescription
    }
}

/// Links shown on the paywall. Set once the marketing site is live; hidden while `nil`.
enum AppLinks {
    static let privacyPolicy: URL? = nil
    static let terms: URL? = nil
}

/// One-time unlock screen (SPEC §13.3). Never shown on launch; opened from the fourth summary
/// or a locked export. Honest copy on iPhones without Apple Intelligence.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.services) private var services
    @Environment(AppState.self) private var appState: AppState?
    @State private var model: PaywallModel?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Unlock VeraFlow")
                    .vfText(VFText.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Not now") { dismiss() }
                    .vfText(VFText.rowLabel, color: VFColor.accent)
                    .frame(minHeight: VFMetric.minHit)
                    .accessibilityIdentifier("paywall.dismiss")
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.top, 18)
            if let model {
                content(model)
            } else {
                ProgressView().tint(VFColor.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(VFColor.background.ignoresSafeArea())
        .task {
            if model == nil {
                let model = PaywallModel(purchases: services.purchases)
                self.model = model
                await model.load()
            }
        }
        .onChange(of: model?.didUnlock ?? false) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private var canSummarize: Bool {
        appState?.capabilities?.canSummarize ?? true
    }

    private func content(_ model: PaywallModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                Text("One purchase. No subscription. Everything stays on \(Platform.yourDevice).")
                    .vfText(VFText.recordingTitle)
                    .padding(.top, 10)

                if !canSummarize {
                    // SPEC §13.3: never mislead buyers on iPhones without Apple Intelligence.
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(VFColor.textTertiary)
                            .accessibilityHidden(true)
                        Text("AI summaries aren't available on \(Platform.thisDevice). The unlock still gives you every export, Reminders, and email drafts, and summaries if you move to an Apple Intelligence–capable \(Platform.deviceNoun).")
                            .vfText(VFText.snippet, color: VFColor.textSecondary)
                    }
                    .padding(VFSpace.cardPaddingH)
                    .background(VFColor.surfaceRaised, in: RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
                }

                VFSettingsGroup {
                    benefit("Unlimited AI summaries and action items", detail: "Free: 3 summaries in total", available: canSummarize)
                    VFHairline()
                    benefit("All templates, now and in v1.x", detail: "General, client meeting, contractor walk-through")
                    VFHairline()
                    benefit("Markdown, PDF, and audio exports", detail: "Free: copy as plain text")
                    VFHairline()
                    benefit("Send action items to Reminders", detail: "With due dates")
                    VFHairline()
                    benefit("Email drafts, including the client follow-up")
                    VFHairline()
                    benefit("Recording, transcripts, and speaker labels stay unlimited for everyone", detail: "Free and unlocked")
                }

                if let used = appState?.freeSummariesUsed, canSummarize {
                    Text("\(min(used, FreeTier.summaryLimit)) of \(FreeTier.summaryLimit) free summaries used.")
                        .vfText(VFText.meta, color: VFColor.textTertiary)
                }

                Button {
                    Task { await model.purchase() }
                } label: {
                    Text(model.isWorking ? "Working…" : (model.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock"))
                }
                .buttonStyle(VFPrimaryPillStyle())
                .disabled(model.isWorking || model.product == nil)
                .opacity(model.isWorking || model.product == nil ? 0.6 : 1)
                .accessibilityIdentifier("paywall.unlock")

                Button("Restore Purchases") {
                    Task { await model.restore() }
                }
                .buttonStyle(VFSecondaryPillStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("paywall.restore")

                if let message = model.message {
                    Text(message)
                        .vfText(VFText.snippet, color: VFColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .onAppear { AccessibilityNotification.Announcement(message).post() }
                }

                HStack(spacing: 16) {
                    if let terms = AppLinks.terms { Link("Terms", destination: terms) }
                    if let privacy = AppLinks.privacyPolicy { Link("Privacy", destination: privacy) }
                }
                .vfText(VFText.meta, color: VFColor.accent)
                .frame(maxWidth: .infinity)
                Text("Family Sharing supported. Payment goes through the App Store; VeraFlow has no account and never sees your recordings.")
                    .vfText(VFText.reassurance, color: VFColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.bottom, VFSpace.bottomInset)
        }
    }

    private func benefit(_ title: String, detail: String? = nil, available: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(available ? VFColor.success : VFColor.textTertiary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .vfText(VFText.rowLabel, color: available ? VFColor.textPrimary : VFColor.textTertiary)
                    .strikethrough(!available)
                if let detail {
                    Text(detail).vfText(VFText.meta, color: VFColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        // Strikethrough isn't spoken; say it (A-21).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([available ? title : "Not available on \(Platform.thisDevice): \(title)", detail].compactMap { $0 }.joined(separator: ". "))
    }
}

#Preview {
    PaywallView()
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
