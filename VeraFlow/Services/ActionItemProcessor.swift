import Foundation

/// Pure Swift deterministic post-processing pipeline for action items (§11.5).
/// Performs deduplication, speaker attribution, date resolution, and timestamp clamping.
public struct ActionItemProcessor: Sendable {
    private let dueDateResolver: DueDateResolverProtocol
    
    public init(dueDateResolver: DueDateResolverProtocol = DueDateResolver()) {
        self.dueDateResolver = dueDateResolver
    }
    
    public func process(
        rawItems: [RawActionItem],
        referenceDate: Date,
        speakers: [AlignedSpeaker],
        segments: [AlignedSegment],
        recordingDuration: TimeInterval
    ) -> [ActionItem] {
        guard !rawItems.isEmpty else { return [] }
        
        // 1. Initial conversion and field parsing
        let candidates: [ActionItem] = rawItems.compactMap { raw in
            let task = cleanTaskString(raw.task)
            guard !task.isEmpty else { return nil }
            
            let (formattedTimestamp, audioTime) = parseAndClampTimestamp(raw.timestamp, maxDuration: recordingDuration)
            let resolvedDate = dueDateResolver.resolve(dueText: raw.dueText, referenceDate: referenceDate).date
            
            let speakerKey = resolveSpeakerKey(
                owner: raw.owner,
                audioTime: audioTime,
                speakers: speakers,
                segments: segments
            )
            
            return ActionItem(
                id: UUID(),
                task: task,
                owner: raw.owner,
                speakerKey: speakerKey,
                dueText: raw.dueText,
                resolvedDueDate: resolvedDate,
                timestamp: formattedTimestamp,
                audioTime: audioTime,
                isCompleted: false
            )
        }
        
        // 2. Deterministic deduplication
        return deduplicate(candidates)
    }
    
    // MARK: - Deduplication (§11.5 #1)
    
    public func deduplicate(_ items: [ActionItem]) -> [ActionItem] {
        var uniqueItems: [ActionItem] = []
        
        for item in items {
            let normCurrent = normalizeForComparison(item.task)
            
            if let existingIndex = uniqueItems.firstIndex(where: {
                let normExisting = normalizeForComparison($0.task)
                return normExisting == normCurrent ||
                       isHighlySimilar(normExisting, normCurrent)
            }) {
                // Merge with existing: keep more specific metadata
                var existing = uniqueItems[existingIndex]
                
                if existing.owner.isEmpty && !item.owner.isEmpty {
                    existing.owner = item.owner
                    existing.speakerKey = item.speakerKey
                }
                if existing.dueText.isEmpty && !item.dueText.isEmpty {
                    existing.dueText = item.dueText
                    existing.resolvedDueDate = item.resolvedDueDate
                }
                if existing.timestamp.isEmpty && !item.timestamp.isEmpty {
                    existing.timestamp = item.timestamp
                    existing.audioTime = item.audioTime
                }
                uniqueItems[existingIndex] = existing
            } else {
                uniqueItems.append(item)
            }
        }
        
        return uniqueItems
    }
    
    // MARK: - Speaker Key Resolution (§11.5 #3)
    
    public func resolveSpeakerKey(
        owner: String,
        audioTime: TimeInterval?,
        speakers: [AlignedSpeaker],
        segments: [AlignedSegment]
    ) -> String? {
        let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Match directly against known speaker keys or display names
        if !trimmedOwner.isEmpty {
            for sp in speakers {
                if sp.key.localizedCaseInsensitiveCompare(trimmedOwner) == .orderedSame ||
                   sp.displayName.localizedCaseInsensitiveCompare(trimmedOwner) == .orderedSame {
                    return sp.key
                }
            }
            
            // "Speaker 1" -> "S1"
            if let num = extractSpeakerNumber(trimmedOwner) {
                let targetKey = "S\(num)"
                if speakers.contains(where: { $0.key == targetKey }) {
                    return targetKey
                }
            }
        }
        
        // Fallback: If audioTime is known, find the segment covering that moment
        if let audioTime {
            if let matchingSeg = segments.first(where: { audioTime >= $0.start && audioTime <= $0.end }) {
                return matchingSeg.speakerKey
            }
        }
        
        return nil
    }
    
    // MARK: - Timestamp Clamping (§11.5 #4)
    
    public func parseAndClampTimestamp(
        _ text: String,
        maxDuration: TimeInterval
    ) -> (formatted: String, time: TimeInterval?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }
        
        // Clean out brackets, parentheses, prefixes
        let cleaned = trimmed
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "▶︎", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let parts = cleaned.components(separatedBy: ":")
        var seconds: TimeInterval = 0
        
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            seconds = m * 60 + s
        } else if parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) {
            seconds = h * 3600 + m * 60 + s
        } else if let direct = Double(cleaned) {
            seconds = direct
        } else {
            return (trimmed, nil)
        }
        
        // Clamp to valid audio bounds
        if maxDuration > 0 {
            seconds = max(0, min(seconds, maxDuration))
        } else {
            seconds = max(0, seconds)
        }
        
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let formatted = String(format: "%02d:%02d", mins, secs)
        
        return (formatted, seconds)
    }
    
    // MARK: - Private Cleaners
    
    private func cleanTaskString(_ raw: String) -> String {
        var task = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["- ", "* ", "• ", "1. ", "2. ", "3. ", "4. ", "5. "]
        for prefix in prefixes {
            if task.hasPrefix(prefix) {
                task = String(task.dropFirst(prefix.count))
            }
        }
        return task.trimmingCharacters(in: .whitespaces)
    }
    
    private func normalizeForComparison(_ task: String) -> String {
        var str = task.lowercased()
        let toRemove = ["to ", "need to ", "must ", "should ", "please ", "will "]
        for prefix in toRemove {
            if str.hasPrefix(prefix) {
                str = String(str.dropFirst(prefix.count))
            }
        }
        return str.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    private func isHighlySimilar(_ s1: String, _ s2: String) -> Bool {
        if s1 == s2 { return true }
        if s1.contains(s2) || s2.contains(s1) {
            let ratio = Double(min(s1.count, s2.count)) / Double(max(s1.count, s2.count))
            return ratio >= 0.75
        }
        return false
    }
    
    private func extractSpeakerNumber(_ text: String) -> Int? {
        let pattern = #"(?:speaker|s)\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            return Int(text[range])
        }
        return nil
    }
}
