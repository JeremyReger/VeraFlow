import Foundation

/// The real aligner (SPEC §10.2): merges timed words with diarizer turns into speaker-labeled
/// paragraphs. Pure Swift. Ported from the Antigravity branch's `TranscriptAligner` (see
/// docs/reviews/2026-09-17-antigravity-review.md) and fitted to `TranscriptAligning`.
struct LiveTranscriptAligner: TranscriptAligning {
    /// A word with no overlapping turn takes the nearest turn within this distance.
    static let nearestTurnThreshold: TimeInterval = 0.5
    /// Runs shorter than this, sandwiched between the same speaker, are reassigned.
    static let minimumRunLength = 3

    var rules: Paragrapher.Rules = .spec

    func paragraphs(from words: [TimedWord]) -> [AlignedSegment] {
        Paragrapher.segments(from: words, rules: rules).map {
            AlignedSegment(start: $0.start, end: $0.end, speakerKey: nil, words: $0.words)
        }
    }

    func align(words: [TimedWord], turns: [SpeakerTurn]) -> [AlignedSegment] {
        guard !words.isEmpty else { return [] }
        guard !turns.isEmpty else { return paragraphs(from: words) }
        let keys = Self.speakerKeys(for: words, turns: turns)

        var segments: [AlignedSegment] = []
        var current: [TimedWord] = []
        var currentKey = keys[0]

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            segments.append(AlignedSegment(start: first.start, end: last.end, speakerKey: currentKey, words: current))
            current = []
        }

        for (word, key) in zip(words, keys) {
            if !current.isEmpty, key != currentKey || Self.shouldBreak(before: word, in: current, rules: rules) {
                flush()
            }
            if current.isEmpty {
                currentKey = key
            }
            current.append(word)
        }
        flush()
        return segments
    }

    func speakerKeys(forSegments segments: [[TimedWord]], turns: [SpeakerTurn]) -> [String?] {
        guard !turns.isEmpty else { return Array(repeating: nil, count: segments.count) }
        let flat = segments.flatMap { $0 }
        guard !flat.isEmpty else { return Array(repeating: nil, count: segments.count) }
        let keys = Self.speakerKeys(for: flat, turns: turns)

        var result: [String?] = []
        var cursor = 0
        var previous: String?
        for segment in segments {
            let slice = keys[cursor ..< cursor + segment.count]
            cursor += segment.count
            if let winner = Self.majority(of: slice) {
                result.append(winner)
                previous = winner
            } else {
                result.append(previous ?? keys.first)
            }
        }
        return result
    }

    // MARK: Word assignment

    /// One `S1…Sn` key per word, after overlap assignment and smoothing.
    static func speakerKeys(for words: [TimedWord], turns: [SpeakerTurn]) -> [String] {
        let sortedTurns = turns.sorted { $0.start < $1.start }
        var raw: [String] = []
        raw.reserveCapacity(words.count)
        var last = sortedTurns[0].speakerID
        for word in words {
            let id = turnID(for: word, in: sortedTurns) ?? last
            raw.append(id)
            last = id
        }
        raw = smoothed(raw)

        var keyByID: [String: String] = [:]
        return raw.map { id in
            if let key = keyByID[id] { return key }
            let key = "S\(keyByID.count + 1)"
            keyByID[id] = key
            return key
        }
    }

    /// Largest overlap, else nearest within `nearestTurnThreshold`, else `nil`.
    private static func turnID(for word: TimedWord, in turns: [SpeakerTurn]) -> String? {
        var best: SpeakerTurn?
        var bestOverlap: TimeInterval = 0
        var nearest: SpeakerTurn?
        var nearestDistance = nearestTurnThreshold
        for turn in turns {
            let overlap = min(word.end, turn.end) - max(word.start, turn.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = turn
            }
            let distance: TimeInterval
            if word.end < turn.start {
                distance = turn.start - word.end
            } else if word.start > turn.end {
                distance = word.start - turn.end
            } else {
                distance = 0
            }
            if distance <= nearestDistance {
                nearestDistance = distance
                nearest = turn
            }
        }
        if let best, bestOverlap > 0 { return best.speakerID }
        return nearest?.speakerID
    }

    /// Reassigns runs shorter than `minimumRunLength` that sit between two runs of the same
    /// other speaker. Repeats until stable (a bounded number of passes).
    static func smoothed(_ ids: [String]) -> [String] {
        var ids = ids
        for _ in 0..<8 {
            var changed = false
            var index = 0
            while index < ids.count {
                var runEnd = index
                while runEnd < ids.count, ids[runEnd] == ids[index] {
                    runEnd += 1
                }
                if runEnd - index < minimumRunLength, index > 0, runEnd < ids.count,
                   ids[index - 1] == ids[runEnd], ids[index - 1] != ids[index] {
                    for k in index..<runEnd {
                        ids[k] = ids[index - 1]
                    }
                    changed = true
                }
                index = runEnd
            }
            if !changed { break }
        }
        return ids
    }

    private static func shouldBreak(before word: TimedWord, in current: [TimedWord], rules: Paragrapher.Rules) -> Bool {
        guard let first = current.first, let last = current.last else { return false }
        if word.start - last.end > rules.maxGap { return true }
        if word.end - first.start > rules.maxDuration { return true }
        return Paragrapher.endsSentence(last.text) && current.count > rules.sentenceWordLimit
    }

    private static func majority(of keys: ArraySlice<String>) -> String? {
        var counts: [String: Int] = [:]
        for key in keys {
            counts[key, default: 0] += 1
        }
        // Ties go to the key that appears first in the slice, so labels stay stable.
        return keys.max { a, b in
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            if ca != cb { return ca < cb }
            return (keys.firstIndex(of: a) ?? 0) > (keys.firstIndex(of: b) ?? 0)
        }
    }
}
