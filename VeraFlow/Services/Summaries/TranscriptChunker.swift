import Foundation

/// A run of transcript lines that fits the model's input budget (SPEC §11.3).
struct TranscriptChunk: Equatable, Sendable {
    /// Indices into the line array, inclusive of the overlap line borrowed from the previous chunk.
    var lineRange: Range<Int>
    var text: String
    var tokenEstimate: Int
}

/// Formats transcript lines for the model and splits them into chunks by token budget. Chunks
/// never split a line, and consecutive chunks share one line so nothing is lost at a boundary.
enum TranscriptChunker {
    /// SPEC §11.2: conservative estimate for iOS 26, where the model can't count tokens.
    static func estimateTokens(_ text: String) -> Int {
        Int((Double(text.count) / 3.5).rounded(.up))
    }

    /// The prefix of a mark line; the shared rules tell the model what it means.
    static let markPrefix = "★ Marked"

    /// `[12:34] Speaker 2: text`, or `[12:34] ★ Marked: Decision` for a user mark.
    static func format(_ line: TranscriptLine) -> String {
        if line.isMark {
            let label = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "[\(timestamp(line.start))] \(markPrefix)" + (label.isEmpty ? "" : ": \(label)")
        }
        return "[\(timestamp(line.start))] \(line.speakerDisplayName): \(line.text)"
    }

    /// "mm:ss", or "h:mm:ss" from one hour on.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    static func text(for lines: [TranscriptLine]) -> String {
        lines.map(format).joined(separator: "\n")
    }

    /// True when the whole transcript fits one call, so MAP can be skipped.
    static func fitsInOneCall(_ lines: [TranscriptLine], budgetTokens: Int, tokenCount: (String) -> Int = estimateTokens) -> Bool {
        tokenCount(text(for: lines)) <= budgetTokens
    }

    static func chunks(
        lines: [TranscriptLine],
        budgetTokens: Int,
        overlap: Int = 1,
        tokenCount: (String) -> Int = estimateTokens
    ) -> [TranscriptChunk] {
        guard !lines.isEmpty else { return [] }
        let formatted = lines.map(format)
        let costs = formatted.map { tokenCount($0) + 1 } // +1 for the newline
        var chunks: [TranscriptChunk] = []
        var start = 0
        while start < lines.count {
            var end = start
            var total = 0
            while end < lines.count, total + costs[end] <= budgetTokens || end == start {
                total += costs[end]
                end += 1
            }
            chunks.append(TranscriptChunk(
                lineRange: start ..< end,
                text: formatted[start ..< end].joined(separator: "\n"),
                tokenEstimate: total
            ))
            guard end < lines.count else { break }
            // Borrow the last `overlap` lines, but always move forward.
            start = max(end - overlap, start + 1)
        }
        return chunks
    }
}

/// How many tokens a call may spend on transcript text (SPEC §11.2).
struct ContextBudget: Equatable, Sendable {
    var contextSize: Int
    var instructionsTokens: Int
    var schemaOverhead: Int
    /// Room for one chunk's notes in the MAP step, which is also the cap on that answer.
    var outputReserve: Int
    /// Room for the whole summary in the FINAL step. Bigger than the MAP reserve on purpose:
    /// see `defaultFinalOutputReserve`.
    var finalOutputReserve: Int

    init(
        contextSize: Int,
        instructionsTokens: Int,
        schemaOverhead: Int,
        outputReserve: Int? = nil,
        finalOutputReserve: Int? = nil
    ) {
        self.contextSize = contextSize
        self.instructionsTokens = instructionsTokens
        self.schemaOverhead = schemaOverhead
        self.outputReserve = outputReserve ?? Self.defaultOutputReserve(for: contextSize)
        self.finalOutputReserve = finalOutputReserve ?? Self.defaultFinalOutputReserve(for: contextSize)
    }

    /// 1,000 tokens on a 4K model, 1,500 on anything larger (SPEC §11.2). Chunk notes are small
    /// and capped by their own schema, so this is the step that can afford to give input the room.
    static func defaultOutputReserve(for contextSize: Int) -> Int {
        contextSize <= 4_096 ? 1_000 : 1_500
    }

    /// The FINAL step is the other way round: its input is a page of notes, and its output is the
    /// whole summary. Priced at the schema's own maximum — an overview, up to eight topics of five
    /// points, decisions, ten action items and open questions, with a JSON key per field — which
    /// runs to 2,500–3,000 tokens. The MAP reserve of 1,500 was also the response cap, so on a
    /// 39-minute meeting the model was cut off mid-array and the answer failed to decode
    /// (DECISIONS.md 2026-09-21). Never more than half the window, so input keeps a working share.
    static func defaultFinalOutputReserve(for contextSize: Int) -> Int {
        max(defaultOutputReserve(for: contextSize), min(contextSize / 2, 3_000))
    }

    /// Tokens left for the transcript itself; never below a small floor so chunking terminates.
    var inputTokens: Int {
        max(200, contextSize - instructionsTokens - schemaOverhead - outputReserve)
    }

    /// Tokens left for the FINAL call's input: the combined notes, or the whole transcript when it
    /// fits one call. Smaller than `inputTokens`, because the answer needs more room than notes do.
    var finalInputTokens: Int {
        max(200, contextSize - instructionsTokens - schemaOverhead - finalOutputReserve)
    }

    /// After `exceededContextWindowSize`: 30 % smaller chunks (SPEC §11.2).
    static func shrunk(_ tokens: Int) -> Int {
        max(200, Int((Double(tokens) * 0.7).rounded(.down)))
    }
}
