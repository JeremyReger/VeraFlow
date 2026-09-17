import SwiftUI
import MessageUI
import UniformTypeIdentifiers

/// Comprehensive export sheet offering Markdown, PDF, Plain Text, Reminders, and Audio sharing (§12).
public struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recording: Recording
    
    private let exportService: ExportServiceProtocol
    private let purchaseService: PurchaseServiceProtocol
    
    @State private var isUnlocked: Bool = false
    @State private var isPaywallPresented: Bool = false
    @State private var includeTranscript: Bool = true
    @State private var toastMessage: String? = nil
    @State private var isSharingItem: ShareableFile? = nil
    @State private var isMailPresented: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportError: String? = nil
    
    public init(
        recording: Recording,
        exportService: ExportServiceProtocol = ExportService(),
        purchaseService: PurchaseServiceProtocol = StoreKitPurchaseService()
    ) {
        self.recording = recording
        self.exportService = exportService
        self.purchaseService = purchaseService
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Header Info
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recording.title)
                            .font(.headline)
                        Text("\(recording.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(formatDuration(recording.duration))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("Include Full Transcript", isOn: $includeTranscript)
                        .font(.subheadline)
                }
                
                // Document Exports
                Section("Documents") {
                    Button {
                        shareMarkdown()
                    } label: {
                        Label("Share Markdown (.md)", systemImage: "arrow.down.doc.fill")
                    }
                    
                    Button {
                        sharePDF()
                    } label: {
                        Label("Export PDF Document (.pdf)", systemImage: "doc.richtext.fill")
                    }
                    
                    Button {
                        copyMarkdownToClipboard()
                    } label: {
                        Label("Copy Markdown to Clipboard", systemImage: "doc.on.clipboard")
                    }
                    
                    Button {
                        copyPlainTextToClipboard()
                    } label: {
                        Label("Copy Plain Text", systemImage: "text.alignleft")
                    }
                }
                
                // Integrations
                Section("Integrations") {
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            isMailPresented = true
                        } else {
                            copyPlainTextToClipboard()
                            showToast("Mail not configured. Copied summary to clipboard.")
                        }
                    } label: {
                        Label("Compose Email Draft", systemImage: "envelope.fill")
                    }
                    
                    Button {
                        syncToReminders()
                    } label: {
                        Label("Sync Action Items to Reminders", systemImage: "checklist")
                    }
                }
                
                // Audio File Export
                Section("Media") {
                    Button {
                        shareAudioM4A()
                    } label: {
                        Label("Export Audio (.m4a)", systemImage: "waveform")
                    }
                }
                
                if let error = exportError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Export & Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $isSharingItem) { file in
                ActivityView(activityItems: [file.url])
            }
            .sheet(isPresented: $isMailPresented) {
                let body = exportService.exportPlainText(recording: recording, includeTranscript: includeTranscript)
                MailComposeView(subject: "Meeting Summary: \(recording.title)", body: body)
            }
            .sheet(isPresented: $isPaywallPresented) {
                PaywallSheet(purchaseService: purchaseService)
            }
            .task {
                let ent = await purchaseService.currentEntitlement()
                isUnlocked = ent.isLifetimeUnlocked
            }
            .overlay(alignment: .bottom) {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
    
    // MARK: - Export Actions
    
    private func shareMarkdown() {
        guard isUnlocked else {
            isPaywallPresented = true
            return
        }
        let md = exportService.exportMarkdown(recording: recording, includeTranscript: includeTranscript)
        let sanitizedTitle = sanitizeFileName(recording.title)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitizedTitle).md")
        
        do {
            try md.write(to: tempURL, atomically: true, encoding: .utf8)
            isSharingItem = ShareableFile(url: tempURL)
        } catch {
            exportError = "Failed to create Markdown file: \(error.localizedDescription)"
        }
    }
    
    private func sharePDF() {
        guard isUnlocked else {
            isPaywallPresented = true
            return
        }
        isExporting = true
        exportError = nil
        
        Task {
            do {
                let pdfData = try await exportService.exportPDFData(recording: recording, includeTranscript: includeTranscript)
                let sanitizedTitle = sanitizeFileName(recording.title)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitizedTitle).pdf")
                try pdfData.write(to: tempURL)
                
                await MainActor.run {
                    isExporting = false
                    isSharingItem = ShareableFile(url: tempURL)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = "PDF generation failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func copyMarkdownToClipboard() {
        let md = exportService.exportMarkdown(recording: recording, includeTranscript: includeTranscript)
        UIPasteboard.general.string = md
        showToast("Markdown copied to clipboard!")
    }
    
    private func copyPlainTextToClipboard() {
        let text = exportService.exportPlainText(recording: recording, includeTranscript: includeTranscript)
        UIPasteboard.general.string = text
        showToast("Plain text copied to clipboard!")
    }
    
    private func syncToReminders() {
        guard isUnlocked else {
            isPaywallPresented = true
            return
        }
        guard let summary = recording.summaries.last,
              let items = try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState),
              !items.isEmpty else {
            showToast("No action items available to sync.")
            return
        }
        
        isExporting = true
        exportError = nil
        
        Task {
            do {
                let ids = try await exportService.exportActionItemsToReminders(actionItems: items, listTitle: nil)
                await MainActor.run {
                    isExporting = false
                    showToast("Synced \(ids.count) action items to Apple Reminders!")
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }
    
    private func shareAudioM4A() {
        guard isUnlocked else {
            isPaywallPresented = true
            return
        }
        let audioFileURL = AppConstants.recordingsDirectoryURL
            .appendingPathComponent(recording.id.uuidString)
            .appendingPathComponent(recording.audioFileName)
        
        let sanitizedTitle = sanitizeFileName(recording.title)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitizedTitle).m4a")
        
        isExporting = true
        exportError = nil
        
        Task {
            do {
                try await exportService.exportAudioM4A(recording: recording, sourceAudioURL: audioFileURL, outputURL: outputURL)
                await MainActor.run {
                    isExporting = false
                    isSharingItem = ShareableFile(url: outputURL)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = "Audio export failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func showToast(_ text: String) {
        withAnimation { toastMessage = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}

public struct ShareableFile: Identifiable {
    public var id: String { url.path }
    public let url: URL
}

public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]? = nil
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
