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
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Unlock VeraFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("paywall.dismiss")
                }
            }
        }
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
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity)
                Text("One purchase. No subscription. Everything stays on your iPhone.")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if !canSummarize {
                    // SPEC §13.3: never mislead buyers on iPhones without Apple Intelligence.
                    Label {
                        Text("AI summaries aren't available on this iPhone. The unlock still gives you every export, Reminders, and email drafts, and summaries if you move to an Apple Intelligence–capable iPhone.")
                    } icon: {
                        Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                    }
                    .font(.footnote)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 10) {
                    benefit("Unlimited AI summaries and action items", detail: "Free: 3 summaries in total", available: canSummarize)
                    benefit("All templates, now and in v1.x", detail: "General, client meeting, contractor walk-through")
                    benefit("Markdown, PDF, and audio exports", detail: "Free: copy as plain text")
                    benefit("Send action items to Reminders", detail: "With due dates")
                    benefit("Email drafts, including the client follow-up")
                    benefit("Recording, transcripts, and speaker labels stay unlimited for everyone", detail: "Free and unlocked")
                }

                if let used = appState?.freeSummariesUsed, canSummarize {
                    Text("\(min(used, FreeTier.summaryLimit)) of \(FreeTier.summaryLimit) free summaries used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await model.purchase() }
                } label: {
                    Text(model.isWorking ? "Working…" : (model.product.map { "Unlock for \($0.displayPrice)" } ?? "Unlock"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.isWorking || model.product == nil)
                .accessibilityIdentifier("paywall.unlock")

                Button("Restore Purchases") {
                    Task { await model.restore() }
                }
                .frame(maxWidth: .infinity)
                .disabled(model.isWorking)
                .accessibilityIdentifier("paywall.restore")

                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }

                HStack(spacing: 16) {
                    if let terms = AppLinks.terms { Link("Terms", destination: terms) }
                    if let privacy = AppLinks.privacyPolicy { Link("Privacy", destination: privacy) }
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                Text("Family Sharing supported. Payment goes through the App Store; VeraFlow has no account and never sees your recordings.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private func benefit(_ title: String, detail: String? = nil, available: Bool = true) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).strikethrough(!available)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

#Preview {
    PaywallView()
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
