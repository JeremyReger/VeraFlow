import Foundation

/// A navigable section of a recording, derived from the summary's topics or areas (v1.1 plan item 12).
struct Chapter: Equatable, Sendable, Identifiable {
    var title: String
    var start: TimeInterval

    var id: String { "\(start)-\(title)" }
}

/// Deterministic clean-up of the start times the model gives topics and areas: parse, clamp,
/// fall back to the transcript, and keep them in order. The model never decides a chapter on
/// its own; a start that can't be placed drops that chapter.
enum ChapterPostProcessor {
    /// Two chapters closer than this are one chapter.
    static let minimumGap: TimeInterval = 20
    /// Words a topic title must share with a paragraph to be placed there when no time was given.
    static let minimumSharedWords = 2

    /// Validated starts, in the order given. `nil` means "no chapter for this one". The first
    /// placed chapter starts at 0:00 so the list covers the whole recording.
    static func starts(
        for titles: [String],
        given: [TimeInterval?],
        duration: TimeInterval,
        segments: [(start: TimeInterval, text: String)]
    ) -> [TimeInterval?] {
        var result: [TimeInterval?] = []
        var last: TimeInterval?
        for (index, title) in titles.enumerated() {
            let raw = index < given.count ? given[index] : nil
            var start = raw.map { min(max(0, $0), max(0, duration)) }
            if start == nil {
                start = nearestSegmentStart(for: title, in: segments)
            }
            guard var placed = start else {
                result.append(nil)
                continue
            }
            if last == nil {
                placed = 0
            } else if let last, placed < last + minimumGap {
                result.append(nil)
                continue
            }
            last = placed
            result.append(placed)
        }
        return result
    }

    /// The earliest paragraph sharing at least `minimumSharedWords` meaningful words with the title.
    static func nearestSegmentStart(for title: String, in segments: [(start: TimeInterval, text: String)]) -> TimeInterval? {
        let tokens = ActionItemPostProcessor.normalizedTokens(title)
        guard tokens.count >= minimumSharedWords else { return nil }
        var best: (start: TimeInterval, shared: Int)?
        for segment in segments {
            let shared = tokens.intersection(ActionItemPostProcessor.normalizedTokens(segment.text)).count
            guard shared >= minimumSharedWords else { continue }
            if let current = best, shared <= current.shared { continue }
            best = (segment.start, shared)
        }
        return best?.start
    }

    /// Chapters from validated (title, start) pairs: only the placed ones, and only when there
    /// are at least two, so a single-subject recording shows nothing.
    static func chapters(titles: [String], starts: [TimeInterval?]) -> [Chapter] {
        let placed = zip(titles, starts).compactMap { title, start -> Chapter? in
            guard let start else { return nil }
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : Chapter(title: cleaned, start: start)
        }
        return placed.count >= 2 ? placed : []
    }
}
