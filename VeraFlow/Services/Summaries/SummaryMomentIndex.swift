import Foundation

/// Where each line of a summary was said, so tapping it can take the player there.
///
/// The model is never asked for these times. It writes the prose; Swift matches that prose back
/// against the transcript, the same way `ActionItemPostProcessor` places an action item that came
/// without a timestamp and `ChapterPostProcessor` places a subject. A line that can't be placed
/// confidently simply isn't tappable — better nothing than the wrong moment.
struct SummaryMomentIndex: Sendable {
    /// Meaningful words a line must share with the transcript before it is placed at all. Two is
    /// enough for a subject heading (`ChapterPostProcessor`), but a summary line is a whole
    /// sentence and two words in common is usually a coincidence.
    static let minimumSharedWords = 3
    /// A summary line is often distilled from a couple of sentences in a row, so a run of up to
    /// this many neighbouring paragraphs counts as one place. The run's first paragraph is where
    /// playback starts.
    static let maximumWindow = 3

    /// Line → where it was said. Keyed by the text the Summary tab draws, so a row only has to
    /// hand back what it is already showing.
    private var starts: [String: TimeInterval] = [:]

    init() {}

    /// - Parameters:
    ///   - displayed: the payload as the Summary tab draws it — translated, with the user's edits
    ///     written in. Its lines are the keys.
    ///   - model: the model's own payload. A translated line shares no words with the transcript,
    ///     so when the displayed line can't be placed the model's line in the same position is
    ///     tried instead. Pass `nil` when the displayed payload *is* the model's.
    ///   - segments: the transcript, in order.
    init(displayed: SummaryPayload, model: SummaryPayload? = nil, segments: [(start: TimeInterval, text: String)]) {
        let transcript = Transcript(segments: segments)
        let lines = Self.lines(of: displayed)
        let modelLines = model.map { Self.lines(of: $0) } ?? []
        // Only positionally comparable when nothing added or removed lines; an edit that did
        // means the user's own text is in their own language anyway, so it matches directly.
        let aligned = modelLines.count == lines.count
        for (index, line) in lines.enumerated() {
            let key = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, starts[key] == nil else { continue }
            if let start = transcript.start(for: key) {
                starts[key] = start
            } else if aligned, let start = transcript.start(for: modelLines[index]) {
                starts[key] = start
            }
        }
    }

    /// Where this line was said, or `nil` if it couldn't be placed.
    func start(for line: String) -> TimeInterval? {
        starts[line.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    var isEmpty: Bool { starts.isEmpty }

    /// Every line the Summary tab draws as prose, in draw order. Action items and measurements
    /// aren't here: they carry their own timestamp and already have a ▶︎ button.
    static func lines(of payload: SummaryPayload) -> [String] {
        switch payload {
        case .general(let summary):
            return summary.keyPoints + summary.topics.flatMap(\.points) + summary.decisions + summary.openQuestions
        case .client(let summary):
            return summary.clientGoals + summary.concerns + summary.decisions
                + summary.openQuestions + summary.topics.flatMap(\.points)
        case .walkthrough(let summary):
            return summary.areas.flatMap(\.tasks) + summary.customerRequests
                + summary.issuesFound + summary.quoteNotes
        }
    }

    /// The transcript with its runs of paragraphs worked out once, so placing thirty lines
    /// doesn't tokenize it thirty times over.
    private struct Transcript {
        /// Every run of one to `maximumWindow` neighbouring paragraphs, shortest first and
        /// earliest first, each with the words it contains and the time it starts.
        let windows: [(start: TimeInterval, tokens: Set<String>)]

        init(segments: [(start: TimeInterval, text: String)]) {
            let tokens = segments.map { ActionItemPostProcessor.normalizedTokens($0.text) }
            var windows: [(start: TimeInterval, tokens: Set<String>)] = []
            for width in 1...SummaryMomentIndex.maximumWindow {
                for index in segments.indices where index + width <= segments.count {
                    var words = tokens[index]
                    for offset in (index + 1)..<(index + width) { words.formUnion(tokens[offset]) }
                    windows.append((segments[index].start, words))
                }
            }
            self.windows = windows
        }

        /// The earliest, tightest run of paragraphs sharing the most words with the line. Runs
        /// come shortest first and earliest first and a later one has to beat the one in hand
        /// outright, so a single paragraph that says it wins over a longer stretch that merely
        /// covers it.
        func start(for line: String) -> TimeInterval? {
            let lineTokens = ActionItemPostProcessor.normalizedTokens(line)
            guard lineTokens.count >= SummaryMomentIndex.minimumSharedWords else { return nil }
            var best: (start: TimeInterval, shared: Int)?
            for window in windows {
                let shared = lineTokens.intersection(window.tokens).count
                guard shared >= SummaryMomentIndex.minimumSharedWords else { continue }
                if let current = best, shared <= current.shared { continue }
                best = (window.start, shared)
            }
            return best?.start
        }
    }
}
