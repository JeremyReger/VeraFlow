import Foundation

/// Deterministic clean-up of model output (SPEC §11.6): de-duplicate action items, map owners to
/// speaker keys, resolve due dates in Swift, and validate timestamps against the recording.
struct ActionItemPostProcessor: Sendable {
    struct Context: Sendable {
        var recordedAt: Date
        var duration: TimeInterval
        /// (key, display name) for every speaker on the recording.
        var speakers: [(key: String, displayName: String)]
        /// (start, text) for every transcript paragraph, in order.
        var segments: [(start: TimeInterval, text: String)]

        init(recordedAt: Date, duration: TimeInterval, speakers: [(key: String, displayName: String)] = [], segments: [(start: TimeInterval, text: String)] = []) {
            self.recordedAt = recordedAt
            self.duration = duration
            self.speakers = speakers
            self.segments = segments
        }
    }

    var dueDates: any DueDateResolving
    var calendar: Calendar = .current
    /// Token-set similarity above which two items are the same task.
    var duplicateThreshold = 0.8

    func process(_ drafts: [ActionItemDraft], context: Context) -> [ActionItem] {
        var items: [ActionItem] = []
        for draft in drafts {
            let task = draft.task.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { continue }
            let owner = draft.owner.trimmingCharacters(in: .whitespacesAndNewlines)
            let dueText = draft.dueText.trimmingCharacters(in: .whitespacesAndNewlines)
            let timestamp = Self.parseTimestamp(draft.timestamp).map { min(max(0, $0), context.duration) }
                ?? Self.nearestSegmentStart(for: task, in: context.segments)
            let item = ActionItem(
                task: task,
                owner: owner,
                ownerSpeakerKey: Self.speakerKey(for: owner, speakers: context.speakers),
                dueText: dueText,
                dueDate: dueText.isEmpty ? nil : dueDates.resolve(dueText, relativeTo: context.recordedAt, calendar: calendar),
                timestamp: timestamp
            )
            if let index = items.firstIndex(where: { Self.isDuplicate($0, item, threshold: duplicateThreshold) }) {
                items[index] = Self.merged(items[index], item)
            } else {
                items.append(item)
            }
        }
        return items
    }

    // MARK: De-duplication

    static let stopwords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "for", "on", "in", "at", "by", "with", "we", "i", "will",
        "should", "need", "needs", "it", "this", "that", "is", "be", "our", "up", "about",
    ]

    static func normalizedTokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { !stopwords.contains($0) }
        )
    }

    /// Jaccard similarity of the two token sets.
    static func similarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 1 }
        return Double(a.intersection(b).count) / Double(union.count)
    }

    static func isDuplicate(_ a: ActionItem, _ b: ActionItem, threshold: Double) -> Bool {
        similarity(normalizedTokens(a.task), normalizedTokens(b.task)) > threshold && ownersCompatible(a, b)
    }

    /// Same owner, or one of them unknown.
    static func ownersCompatible(_ a: ActionItem, _ b: ActionItem) -> Bool {
        if let ka = a.ownerSpeakerKey, let kb = b.ownerSpeakerKey { return ka == kb }
        let oa = a.owner.lowercased().trimmingCharacters(in: .whitespaces)
        let ob = b.owner.lowercased().trimmingCharacters(in: .whitespaces)
        return oa.isEmpty || ob.isEmpty || oa == ob
    }

    /// Longer task text, earliest timestamp, and whichever fields the other left empty.
    static func merged(_ kept: ActionItem, _ other: ActionItem) -> ActionItem {
        var result = kept
        if other.task.count > kept.task.count { result.task = other.task }
        switch (kept.timestamp, other.timestamp) {
        case (let a?, let b?): result.timestamp = min(a, b)
        case (nil, let b?): result.timestamp = b
        default: break
        }
        if result.owner.isEmpty { result.owner = other.owner }
        if result.ownerSpeakerKey == nil { result.ownerSpeakerKey = other.ownerSpeakerKey }
        if result.dueText.isEmpty {
            result.dueText = other.dueText
            result.dueDate = other.dueDate
        }
        return result
    }

    // MARK: Owners

    /// "Speaker 2" → "S2"; a renamed speaker's display name → its key; anything else → `nil`.
    static func speakerKey(for owner: String, speakers: [(key: String, displayName: String)]) -> String? {
        let trimmed = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let match = trimmed.range(of: #"^speaker\s+(\d+)$"#, options: [.regularExpression, .caseInsensitive]) {
            let digits = trimmed[match].filter(\.isNumber)
            let key = "S\(digits)"
            return speakers.isEmpty || speakers.contains { $0.key == key } ? key : nil
        }
        return speakers.first { $0.displayName.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }?.key
    }

    // MARK: Timestamps

    /// "mm:ss", "h:mm:ss", optionally in brackets.
    static func parseTimestamp(_ text: String) -> TimeInterval? {
        let cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] \n"))
        let parts = cleaned.split(separator: ":").map { Int($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        let numbers = parts.compactMap { $0 }
        guard numbers.dropFirst().allSatisfy({ (0..<60).contains($0) }) else { return nil }
        switch numbers.count {
        case 3: return TimeInterval(numbers[0] * 3_600 + numbers[1] * 60 + numbers[2])
        case 2: return TimeInterval(numbers[0] * 60 + numbers[1])
        default: return nil
        }
    }

    /// The earliest paragraph sharing at least three meaningful words with the task, preferring
    /// the one with the most shared words.
    static func nearestSegmentStart(for task: String, in segments: [(start: TimeInterval, text: String)]) -> TimeInterval? {
        let taskTokens = normalizedTokens(task)
        guard taskTokens.count >= 3 else { return nil }
        var best: (start: TimeInterval, shared: Int)?
        for segment in segments {
            let shared = taskTokens.intersection(normalizedTokens(segment.text)).count
            guard shared >= 3 else { continue }
            if let current = best, shared <= current.shared { continue }
            best = (segment.start, shared)
        }
        return best?.start
    }
}
