import Foundation
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Which file to produce for the share sheet.
enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case plainText
    case pdf
    case audio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .plainText: "Plain text"
        case .pdf: "PDF"
        case .audio: "Audio (.m4a)"
        }
    }

    var systemImage: String {
        switch self {
        case .markdown: "number"
        case .plainText: "doc.plaintext"
        case .pdf: "doc.richtext"
        case .audio: "waveform"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .pdf: "pdf"
        case .audio: "m4a"
        }
    }
}

/// A file ready for the share sheet.
struct ShareItem: Identifiable, Equatable {
    var url: URL
    var id: String { url.path }
}

/// An email to compose.
struct MailDraft: Identifiable, Equatable {
    var subject: String
    var body: String
    var id: String { subject + body }
}

/// Drives the share menu on the detail screen (SPEC §4.5, §12): builds files in a temporary
/// folder, copies text, drafts email, and reports errors.
@Observable
@MainActor
final class ExportController {
    var shareItem: ShareItem?
    var mailDraft: MailDraft?
    var errorMessage: String?
    private(set) var isWorking = false

    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    /// Writes the export to a temporary file and presents the share sheet.
    func share(_ kind: ExportKind, document: ExportDocument, audioURL: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let name = await services.exporter.fileName(for: document, fileExtension: kind.fileExtension)
            let url = Self.exportsDirectory().appending(path: name)
            try? FileManager.default.removeItem(at: url)
            // Exports hold the full transcript: complete protection while they wait in tmp, and
            // they are removed when the share sheet closes (security review S-5).
            let options: Data.WritingOptions = [.atomic, .completeFileProtection]
            switch kind {
            case .markdown:
                let text = try await services.exporter.markdown(for: document)
                try Data(text.utf8).write(to: url, options: options)
            case .plainText:
                let text = try await services.exporter.plainText(for: document)
                try Data(text.utf8).write(to: url, options: options)
            case .pdf:
                try await services.exporter.pdf(for: document).write(to: url, options: options)
            case .audio:
                try await services.exporter.exportAudio(from: audioURL, to: url)
                try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            }
            shareItem = ShareItem(url: url)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Removes the shared file once the share sheet is gone.
    func finishSharing() {
        if let url = shareItem?.url {
            try? FileManager.default.removeItem(at: url)
        }
        shareItem = nil
    }

    func copySummary(_ document: ExportDocument) {
        Self.copyToPasteboard(ExportRenderer.summaryText(for: document))
    }

    func copyActionItems(_ document: ExportDocument) {
        Self.copyToPasteboard(ExportRenderer.actionItemsText(for: document))
    }

    /// Stays on this device (no Universal Clipboard) and expires after two minutes (S-4).
    /// iOS refuses pasteboard writes while the app is inactive, which it briefly is while the
    /// menu that triggered the copy is closing ("Pasteboard … is not available at this time"),
    /// so the write waits for the app to be active again.
    static func copyToPasteboard(_ text: String) {
        Task { @MainActor in
            for _ in 0..<20 where UIApplication.shared.applicationState != .active {
                try? await Task.sleep(for: .milliseconds(100))
            }
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: text]],
                options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
            )
            AccessibilityNotification.Announcement("Copied").post()
        }
    }

    /// Summary + action items as an email, or the model-written follow-up for the client template.
    func draftEmail(for document: ExportDocument) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if case .client(let summary)? = document.summary {
                let email = try await services.summarization.followUpEmail(for: summary)
                // Model-written text: no links or markup ride into Mail (S-14).
                mailDraft = MailDraft(
                    subject: TextSanitizer.stripLinksAndMarkup(email.subject),
                    body: TextSanitizer.stripLinksAndMarkupKeepingLines(email.body)
                )
            } else {
                mailDraft = MailDraft(subject: document.title, body: ExportRenderer.emailBody(for: document))
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    static func exportsDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func message(for error: Error) -> String {
        if let error = error as? ExportError {
            switch error {
            case .remindersAccessDenied: return "VeraFlow doesn't have access to Reminders. You can allow it in Settings → Privacy & Security → Reminders."
            case .remindersFailed(let detail): return "Couldn't create the reminders: \(detail)"
            case .pdfFailed(let detail): return "Couldn't make the PDF: \(detail)"
            case .audioExportFailed(let detail): return "Couldn't export the audio: \(detail)"
            case .mailUnavailable: return "Mail isn't set up on this iPhone. Use the share sheet instead."
            }
        }
        if let error = error as? SummarizationError {
            return PipelineFailure.message(for: error)
        }
        return error.localizedDescription
    }
}
