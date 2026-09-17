import Foundation
import UIKit
import EventKit
import AVFoundation

/// Production export engine handling Markdown, PDF, Plain Text, Reminders, and Audio M4A (§12).
@MainActor
public final class ExportService: ExportServiceProtocol, Sendable {
    
    public init() {}
    
    // MARK: - Markdown Export (§12)
    
    public func exportMarkdown(recording: Recording, includeTranscript: Bool) -> String {
        var lines: [String] = []
        
        lines.append("# \(recording.title)")
        lines.append("")
        
        let dateStr = recording.createdAt.formatted(date: .abbreviated, time: .shortened)
        let durationStr = formatDuration(recording.duration)
        lines.append("- **Date:** \(dateStr)")
        lines.append("- **Duration:** \(durationStr)")
        
        if let summary = recording.summaries.last {
            lines.append("- **Template:** \(summary.templateID.title)")
            lines.append("- **Engine:** \(summary.modelInfo)")
            lines.append("")
            
            // Render template sections
            lines.append(renderTemplateMarkdown(summary: summary))
            
            // Render Action Items
            if let items = try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState), !items.isEmpty {
                lines.append("## Action Items")
                lines.append("")
                for item in items {
                    let check = item.isCompleted ? "[x]" : "[ ]"
                    var itemLine = "- \(check) \(item.task)"
                    var metaParts: [String] = []
                    
                    let ownerName = displaySpeakerName(for: item.speakerKey, in: recording) ?? item.owner
                    if !ownerName.isEmpty {
                        metaParts.append("**\(ownerName)**")
                    }
                    if !item.dueText.isEmpty {
                        metaParts.append("*(Due: \(item.dueText))*")
                    }
                    if !item.timestamp.isEmpty {
                        metaParts.append("`\(item.timestamp)`")
                    }
                    if !metaParts.isEmpty {
                        itemLine += " — " + metaParts.joined(separator: " • ")
                    }
                    lines.append(itemLine)
                }
                lines.append("")
            }
        }
        
        // Render Bookmarks
        if !recording.bookmarks.isEmpty {
            lines.append("## Bookmarks")
            lines.append("")
            for b in recording.bookmarks {
                let timeStr = formatTime(b.time)
                lines.append("- `\(timeStr)` — \(b.note ?? "Bookmark")")
            }
            lines.append("")
        }
        
        // Render Transcript
        if includeTranscript && !recording.segments.isEmpty {
            lines.append("## Full Transcript")
            lines.append("")
            for segment in recording.segments.sorted(by: { $0.start < $1.start }) {
                let timeStr = formatTime(segment.start)
                let speakerName = displaySpeakerName(for: segment.speakerKey, in: recording) ?? segment.speakerKey ?? "Speaker"
                lines.append("**[\(timeStr)] \(speakerName):** \(segment.text)")
                lines.append("")
            }
        }
        
        lines.append("---")
        lines.append("*Generated privately on-device with VeraFlow.*")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Plain Text Export (§12)
    
    public func exportPlainText(recording: Recording, includeTranscript: Bool) -> String {
        var lines: [String] = []
        
        lines.append(recording.title.uppercased())
        lines.append(String(repeating: "=", count: min(40, recording.title.count)))
        lines.append("Date: \(recording.createdAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("Duration: \(formatDuration(recording.duration))")
        lines.append("")
        
        if let summary = recording.summaries.last {
            lines.append("TEMPLATE: \(summary.templateID.title)")
            lines.append("")
            
            // Plain summary body
            lines.append(renderTemplatePlainText(summary: summary))
            
            if let items = try? JSONDecoder().decode([ActionItem].self, from: summary.actionItemsState), !items.isEmpty {
                lines.append("ACTION ITEMS:")
                for item in items {
                    let status = item.isCompleted ? "[DONE]" : "[TODO]"
                    var desc = "\(status) \(item.task)"
                    let ownerName = displaySpeakerName(for: item.speakerKey, in: recording) ?? item.owner
                    if !ownerName.isEmpty {
                        desc += " (Owner: \(ownerName))"
                    }
                    if !item.dueText.isEmpty {
                        desc += " (Due: \(item.dueText))"
                    }
                    if !item.timestamp.isEmpty {
                        desc += " [\(item.timestamp)]"
                    }
                    lines.append("• " + desc)
                }
                lines.append("")
            }
        }
        
        if includeTranscript && !recording.segments.isEmpty {
            lines.append("TRANSCRIPT:")
            for segment in recording.segments.sorted(by: { $0.start < $1.start }) {
                let timeStr = formatTime(segment.start)
                let speakerName = displaySpeakerName(for: segment.speakerKey, in: recording) ?? segment.speakerKey ?? "Speaker"
                lines.append("[\(timeStr)] \(speakerName): \(segment.text)")
            }
            lines.append("")
        }
        
        lines.append("Generated privately on-device with VeraFlow.")
        return lines.joined(separator: "\n")
    }
    
    // MARK: - PDF Export (§12)
    
    public func exportPDFData(recording: Recording, includeTranscript: Bool) async throws -> Data {
        let plainContent = exportPlainText(recording: recording, includeTranscript: includeTranscript)
        
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter (8.5 x 11 in)
        let margin: CGFloat = 40.0
        let printableWidth = pageBounds.width - (margin * 2)
        let printableHeight = pageBounds.height - (margin * 2)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        
        let data = renderer.pdfData { context in
            // Configure typographic attributes
            let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
            let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
            let headerFont = UIFont.systemFont(ofSize: 9, weight: .medium)
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 3
            paragraphStyle.paragraphSpacing = 8
            
            let fullText = NSMutableAttributedString(string: plainContent, attributes: [
                .font: bodyFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ])
            
            // Format first line as Title
            if let firstLineRange = plainContent.range(of: "\n") {
                let titleLength = plainContent.distance(from: plainContent.startIndex, to: firstLineRange.lowerBound)
                fullText.addAttributes([
                    .font: titleFont,
                    .foregroundColor: UIColor.systemPurple
                ], range: NSRange(location: 0, length: titleLength))
            }
            
            let framesetter = CTFramesetterCreateWithAttributedString(fullText as CFAttributedString)
            var currentRange = CFRange(location: 0, length: 0)
            var pageIndex = 1
            
            while currentRange.location < fullText.length {
                context.beginPage()
                let cgContext = context.cgContext
                
                // Flip coordinate system for CoreText
                cgContext.saveGState()
                cgContext.translateBy(x: 0, y: pageBounds.height)
                cgContext.scaleBy(x: 1.0, y: -1.0)
                
                let path = CGPath(rect: CGRect(x: margin, y: margin, width: printableWidth, height: printableHeight), transform: nil)
                let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
                CTFrameDraw(frame, cgContext)
                
                cgContext.restoreGState()
                
                // Draw footer with page number
                let footerText = "VeraFlow • Page \(pageIndex)"
                let footerAttributes: [NSAttributedString.Key: Any] = [
                    .font: headerFont,
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let footerSize = (footerText as NSString).size(withAttributes: footerAttributes)
                let footerPoint = CGPoint(
                    x: pageBounds.width - margin - footerSize.width,
                    y: pageBounds.height - margin + 12
                )
                (footerText as NSString).draw(at: footerPoint, withAttributes: footerAttributes)
                
                let visibleRange = CTFrameGetVisibleStringRange(frame)
                if visibleRange.length == 0 { break }
                currentRange.location += visibleRange.length
                pageIndex += 1
            }
        }
        
        return data
    }
    
    // MARK: - EventKit Reminders Sync (§12)
    
    public func exportActionItemsToReminders(actionItems: [ActionItem], listTitle: String?) async throws -> [String] {
        let store = EKEventStore()
        
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        
        guard granted else {
            throw ExportError.remindersAccessDenied
        }
        
        // Find default or requested reminders calendar
        let calendars = store.calendars(for: .reminder)
        let targetCalendar: EKCalendar?
        if let listTitle, let match = calendars.first(where: { $0.title.localizedCaseInsensitiveCompare(listTitle) == .orderedSame }) {
            targetCalendar = match
        } else {
            targetCalendar = store.defaultCalendarForNewReminders() ?? calendars.first
        }
        
        guard let targetCalendar else {
            throw ExportError.remindersListNotFound
        }
        
        var generatedIDs: [String] = []
        
        for item in actionItems where !item.isCompleted {
            let reminder = EKReminder(eventStore: store)
            reminder.title = item.task
            reminder.calendar = targetCalendar
            
            var notes: [String] = []
            if !item.owner.isEmpty { notes.append("Owner: \(item.owner)") }
            if !item.timestamp.isEmpty { notes.append("Audio Timestamp: \(item.timestamp)") }
            if !notes.isEmpty {
                reminder.notes = notes.joined(separator: " • ")
            }
            
            if let dueDate = item.resolvedDueDate {
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                reminder.dueDateComponents = comps
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
            
            try store.save(reminder, commit: false)
            generatedIDs.append(reminder.calendarItemIdentifier)
        }
        
        try store.commit()
        return generatedIDs
    }
    
    // MARK: - Audio M4A Export (§12)
    
    public func exportAudioM4A(recording: Recording, sourceAudioURL: URL, outputURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: sourceAudioURL.path) else {
            throw ExportError.audioSourceFileNotFound
        }
        
        // If already m4a, copy directly
        if sourceAudioURL.pathExtension.lowercased() == "m4a" {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: sourceAudioURL, to: outputURL)
            return
        }
        
        // Transcode CAF / WAV / AAC to standard M4A with AVAssetExportSession
        let asset = AVURLAsset(url: sourceAudioURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExportError.audioExportFailed("Unable to create AVAssetExportSession.")
        }
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        if #available(iOS 18.0, *) {
            do {
                try await exportSession.export(to: outputURL, as: .m4a)
            } catch {
                throw ExportError.audioExportFailed(error.localizedDescription)
            }
        } else {
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .m4a
            await exportSession.export()
            if exportSession.status != .completed {
                let err = exportSession.error?.localizedDescription ?? "Unknown export failure"
                throw ExportError.audioExportFailed(err)
            }
        }
    }
    
    // MARK: - Format Helpers
    
    private func renderTemplateMarkdown(summary: SummaryRecord) -> String {
        var lines: [String] = []
        
        switch summary.templateID {
        case .general:
            if let output = try? JSONDecoder().decode(GeneralMeetingOutput.self, from: summary.payloadJSON) {
                lines.append("## Overview")
                lines.append(output.overview)
                lines.append("")
                
                if !output.keyDiscussionPoints.isEmpty {
                    lines.append("## Key Discussion Points")
                    for pt in output.keyDiscussionPoints { lines.append("- \(pt)") }
                    lines.append("")
                }
                
                if !output.decisions.isEmpty {
                    lines.append("## Decisions Made")
                    for d in output.decisions { lines.append("- \(d)") }
                    lines.append("")
                }
            }
            
        case .client:
            if let output = try? JSONDecoder().decode(ClientConsultingOutput.self, from: summary.payloadJSON) {
                lines.append("## Executive Summary")
                lines.append(output.executiveSummary)
                lines.append("")
                
                if !output.clientNeedsAndGoals.isEmpty {
                    lines.append("## Client Needs & Goals")
                    for g in output.clientNeedsAndGoals { lines.append("- \(g)") }
                    lines.append("")
                }
                
                if !output.proposedSolutionsAndScope.isEmpty {
                    lines.append("## Proposed Solutions & Scope")
                    for s in output.proposedSolutionsAndScope { lines.append("- \(s)") }
                    lines.append("")
                }
                
                if !output.commercialsAndTimeline.isEmpty {
                    lines.append("## Commercials & Timeline")
                    lines.append(output.commercialsAndTimeline)
                    lines.append("")
                }
            }
            
        case .walkthrough:
            if let output = try? JSONDecoder().decode(ContractorWalkthroughOutput.self, from: summary.payloadJSON) {
                if !output.locationAndContext.isEmpty {
                    lines.append("## Location & Context")
                    lines.append(output.locationAndContext)
                    lines.append("")
                }
                
                if !output.scopeOfWork.isEmpty {
                    lines.append("## Scope of Work & Measurements")
                    for s in output.scopeOfWork { lines.append("- \(s)") }
                    lines.append("")
                }
                
                if !output.materialsAndEquipment.isEmpty {
                    lines.append("## Materials & Equipment")
                    for m in output.materialsAndEquipment { lines.append("- \(m)") }
                    lines.append("")
                }
                
                if !output.hazardsAndConstraints.isEmpty {
                    lines.append("## Hazards & Constraints")
                    for h in output.hazardsAndConstraints { lines.append("- \(h)") }
                    lines.append("")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func renderTemplatePlainText(summary: SummaryRecord) -> String {
        var lines: [String] = []
        
        switch summary.templateID {
        case .general:
            if let output = try? JSONDecoder().decode(GeneralMeetingOutput.self, from: summary.payloadJSON) {
                lines.append("OVERVIEW:\n\(output.overview)\n")
                if !output.keyDiscussionPoints.isEmpty {
                    lines.append("KEY DISCUSSION POINTS:")
                    for pt in output.keyDiscussionPoints { lines.append("• \(pt)") }
                    lines.append("")
                }
                if !output.decisions.isEmpty {
                    lines.append("DECISIONS MADE:")
                    for d in output.decisions { lines.append("• \(d)") }
                    lines.append("")
                }
            }
            
        case .client:
            if let output = try? JSONDecoder().decode(ClientConsultingOutput.self, from: summary.payloadJSON) {
                lines.append("EXECUTIVE SUMMARY:\n\(output.executiveSummary)\n")
                if !output.clientNeedsAndGoals.isEmpty {
                    lines.append("CLIENT GOALS:")
                    for g in output.clientNeedsAndGoals { lines.append("• \(g)") }
                    lines.append("")
                }
                if !output.proposedSolutionsAndScope.isEmpty {
                    lines.append("PROPOSED SOLUTIONS & SCOPE:")
                    for s in output.proposedSolutionsAndScope { lines.append("• \(s)") }
                    lines.append("")
                }
                if !output.commercialsAndTimeline.isEmpty {
                    lines.append("COMMERCIALS & TIMELINE:\n\(output.commercialsAndTimeline)\n")
                }
            }
            
        case .walkthrough:
            if let output = try? JSONDecoder().decode(ContractorWalkthroughOutput.self, from: summary.payloadJSON) {
                if !output.locationAndContext.isEmpty {
                    lines.append("LOCATION & CONTEXT:\n\(output.locationAndContext)\n")
                }
                if !output.scopeOfWork.isEmpty {
                    lines.append("SCOPE OF WORK & MEASUREMENTS:")
                    for s in output.scopeOfWork { lines.append("• \(s)") }
                    lines.append("")
                }
                if !output.materialsAndEquipment.isEmpty {
                    lines.append("MATERIALS & EQUIPMENT:")
                    for m in output.materialsAndEquipment { lines.append("• \(m)") }
                    lines.append("")
                }
                if !output.hazardsAndConstraints.isEmpty {
                    lines.append("HAZARDS & CONSTRAINTS:")
                    for h in output.hazardsAndConstraints { lines.append("• \(h)") }
                    lines.append("")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func displaySpeakerName(for key: String?, in recording: Recording) -> String? {
        guard let key else { return nil }
        return recording.speakers.first(where: { $0.key == key })?.displayName ?? key
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

public enum ExportError: LocalizedError, Sendable {
    case audioSourceFileNotFound
    case audioExportFailed(String)
    case remindersAccessDenied
    case remindersListNotFound
    
    public var errorDescription: String? {
        switch self {
        case .audioSourceFileNotFound: "Source audio recording file could not be found."
        case .audioExportFailed(let reason): "Failed to export audio: \(reason)"
        case .remindersAccessDenied: "Permission to access Apple Reminders was denied. Enable Reminders in Settings."
        case .remindersListNotFound: "Could not find a valid Reminders list to save action items."
        }
    }
}
