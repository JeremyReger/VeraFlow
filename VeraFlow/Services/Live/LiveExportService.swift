import AVFoundation
import CoreText
import EventKit
import Foundation
import os
import UIKit

/// Exports (SPEC §12): Markdown / plain text from `ExportRenderer`, a paginated PDF with page
/// numbers, action items into Reminders through EventKit, and an `.m4a` copy of the audio.
actor LiveExportService: ExportService {
    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "export")

    /// Confined to this actor; EventKit objects aren't Sendable.
    private let store = EKEventStore()

    func markdown(for document: ExportDocument) async -> String {
        ExportRenderer.markdown(for: document)
    }

    func plainText(for document: ExportDocument) async -> String {
        ExportRenderer.plainText(for: document)
    }

    func pdf(for document: ExportDocument) async throws -> Data {
        let data = PDFComposer.render(document)
        guard !data.isEmpty else { throw ExportError.pdfFailed("No pages were produced.") }
        return data
    }

    func fileName(for document: ExportDocument, fileExtension: String) async -> String {
        ExportRenderer.fileName(for: document, fileExtension: fileExtension)
    }

    // MARK: Reminders

    func reminderLists() async throws -> [ReminderList] {
        try await ensureRemindersAccess()
        let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        return store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { a, b in
                if a.id == defaultID { return true }
                if b.id == defaultID { return false }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    func createReminders(_ requests: [ReminderRequest], in list: ReminderList) async throws -> [UUID: String] {
        try await ensureRemindersAccess()
        guard let calendar = store.calendar(withIdentifier: list.id) else {
            throw ExportError.remindersFailed("That Reminders list no longer exists.")
        }
        var identifiers: [UUID: String] = [:]
        do {
            for request in requests {
                let reminder = EKReminder(eventStore: store)
                reminder.title = request.actionItem.task
                reminder.notes = ExportRenderer.reminderNotes(for: request)
                reminder.calendar = calendar
                if let dueDate = request.actionItem.dueDate {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                    reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
                }
                try store.save(reminder, commit: false)
                identifiers[request.actionItem.id] = reminder.calendarItemIdentifier
            }
            try store.commit()
        } catch {
            store.reset()
            throw ExportError.remindersFailed(error.localizedDescription)
        }
        Self.log.info("created \(identifiers.count, privacy: .public) reminders")
        return identifiers
    }

    private func ensureRemindersAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .denied, .restricted:
            throw ExportError.remindersAccessDenied
        default:
            break
        }
        // The completion-handler form keeps the non-Sendable store inside the actor.
        let granted: Bool = try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: ExportError.remindersFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
        guard granted else { throw ExportError.remindersAccessDenied }
    }

    // MARK: Audio

    func exportAudio(from sourceURL: URL, to destination: URL) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ExportError.audioExportFailed("This audio can't be exported.")
        }
        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw ExportError.audioExportFailed(error.localizedDescription)
        }
    }
}

/// US Letter PDF with a title, the plain-text sections, and "Title · Page n" footers.
enum PDFComposer {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54

    static func render(_ document: ExportDocument) -> Data {
        let text = attributedText(for: document)
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let contentRect = pageRect.insetBy(dx: margin, dy: margin + 16)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        // Title and creator metadata so readers and screen readers know what the file is (A-17).
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "VeraFlow",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
        ]

        return renderer.pdfData { context in
            var location = 0
            var page = 0
            repeat {
                context.beginPage()
                page += 1
                let path = CGPath(rect: contentRect, transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
                let cg = context.cgContext
                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: 0, y: pageRect.height)
                cg.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cg)
                cg.restoreGState()

                let footer = "\(document.title) · Page \(page)" as NSString
                footer.draw(at: CGPoint(x: margin, y: pageRect.height - margin + 4), withAttributes: footerAttributes)

                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { break }
                location += visible.length
            } while location < text.length
        }
    }

    static func attributedText(for document: ExportDocument) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func paragraph(spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 4) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = spacingBefore
            style.paragraphSpacing = spacingAfter
            style.lineBreakMode = .byWordWrapping
            return style
        }
        func append(_ string: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black, style: NSParagraphStyle) {
            result.append(NSAttributedString(string: string + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: style,
            ]))
        }

        append(document.title, size: 20, weight: .bold, style: paragraph(spacingAfter: 2))
        append(ExportRenderer.metadataLine(document), size: 10, color: .darkGray, style: paragraph(spacingAfter: 10))
        if !document.speakers.isEmpty {
            append("Speakers: " + document.speakers.map(\.displayName).joined(separator: ", "), size: 10, color: .darkGray, style: paragraph(spacingAfter: 10))
        }
        for section in ExportRenderer.summarySections(document) {
            append(section.heading, size: 13, weight: .semibold, style: paragraph(spacingBefore: 8, spacingAfter: 3))
            for line in section.lines {
                append(line.hasPrefix("- ") ? "•  " + String(line.dropFirst(2)) : line, size: 11, style: paragraph(spacingAfter: 2))
            }
        }
        if let summary = document.summary, !summary.actionItems.isEmpty {
            append("Action items", size: 13, weight: .semibold, style: paragraph(spacingBefore: 8, spacingAfter: 3))
            for item in summary.actionItems {
                append("☐  " + ExportRenderer.actionItemLine(item, document: document), size: 11, style: paragraph(spacingAfter: 2))
            }
        }
        if case .walkthrough(let summary)? = document.summary, summary.areas.contains(where: { !$0.measurements.isEmpty }) {
            append("Check measurements against the audio before quoting.", size: 10, weight: .medium, color: .darkGray, style: paragraph(spacingBefore: 6, spacingAfter: 6))
        }
        if document.summary != nil {
            append(ExportRenderer.aiDisclaimer, size: 10, weight: .medium, color: .darkGray, style: paragraph(spacingBefore: 6, spacingAfter: 6))
        }
        if document.includeTranscript, !document.segments.isEmpty {
            append("Transcript", size: 13, weight: .semibold, style: paragraph(spacingBefore: 10, spacingAfter: 3))
            for segment in document.segments {
                let stamp = "[\(TranscriptChunker.timestamp(segment.start))] \(document.speakerName(for: segment.speakerKey)): "
                let line = NSMutableAttributedString(string: stamp, attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: UIColor.darkGray,
                    .paragraphStyle: paragraph(spacingAfter: 3),
                ])
                line.append(NSAttributedString(string: segment.text + "\n", attributes: [
                    .font: UIFont.systemFont(ofSize: 10.5),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph(spacingAfter: 3),
                ]))
                result.append(line)
            }
        }
        return result
    }
}
