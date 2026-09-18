import Foundation
import Testing
@testable import VeraFlow

struct TranscriptChunkerTests {
    private func lines(_ count: Int) -> [TranscriptLine] {
        (0..<count).map { index in
            TranscriptLine(start: Double(index) * 30, speakerKey: "S\(index % 2 + 1)", speakerDisplayName: "Speaker \(index % 2 + 1)", text: "Line \(index) text")
        }
    }

    @Test("Lines are formatted as [mm:ss] Name: text, with hours when needed")
    func formatting() {
        #expect(TranscriptChunker.timestamp(0) == "00:00")
        #expect(TranscriptChunker.timestamp(754) == "12:34")
        #expect(TranscriptChunker.timestamp(3_723) == "1:02:03")
        let line = TranscriptLine(start: 754, speakerKey: "S2", speakerDisplayName: "Speaker 2", text: "We need the permit before we pour the footer.")
        #expect(TranscriptChunker.format(line) == "[12:34] Speaker 2: We need the permit before we pour the footer.")
        #expect(TranscriptChunker.estimateTokens("1234567") == 2)
    }

    @Test("Chunks never split a line, respect the budget, and overlap by one line")
    func chunking() {
        let constant: (String) -> Int = { _ in 10 } // every line costs 11 with its newline
        let chunks = TranscriptChunker.chunks(lines: lines(5), budgetTokens: 45, tokenCount: constant)
        #expect(chunks.map(\.lineRange) == [0..<4, 3..<5])
        #expect(chunks.allSatisfy { $0.tokenEstimate <= 45 })
        #expect(chunks[0].text.split(separator: "\n").count == 4)
        #expect(chunks[1].text.hasPrefix("[01:30] Speaker 2: Line 3 text"))

        let pairs = TranscriptChunker.chunks(lines: lines(5), budgetTokens: 25, tokenCount: constant)
        #expect(pairs.map(\.lineRange) == [0..<2, 1..<3, 2..<4, 3..<5])
    }

    @Test("A line bigger than the budget gets its own chunk, and the chunker still moves forward")
    func oversizedLine() {
        let chunks = TranscriptChunker.chunks(lines: lines(3), budgetTokens: 5, tokenCount: { _ in 10 })
        #expect(chunks.map(\.lineRange) == [0..<1, 1..<2, 2..<3])
        #expect(TranscriptChunker.chunks(lines: [], budgetTokens: 100).isEmpty)
    }

    @Test("Short transcripts fit one call so MAP is skipped")
    func fitsInOne() {
        #expect(TranscriptChunker.fitsInOneCall(lines(3), budgetTokens: 1_000))
        #expect(!TranscriptChunker.fitsInOneCall(lines(3), budgetTokens: 10))
        #expect(TranscriptChunker.chunks(lines: lines(3), budgetTokens: 1_000).count == 1)
    }

    @Test("The budget leaves room for instructions, schema, and output; overflow shrinks by 30 %")
    func budget() {
        let small = ContextBudget(contextSize: 4_096, instructionsTokens: 300, schemaOverhead: 200)
        #expect(small.outputReserve == 1_000)
        #expect(small.inputTokens == 2_596)
        let large = ContextBudget(contextSize: 8_192, instructionsTokens: 300, schemaOverhead: 200)
        #expect(large.outputReserve == 1_500)
        #expect(large.inputTokens == 6_192)
        #expect(ContextBudget.shrunk(1_000) == 700)
        #expect(ContextBudget.shrunk(100) == 200, "never below the floor")
        #expect(ContextBudget(contextSize: 500, instructionsTokens: 400, schemaOverhead: 400).inputTokens == 200)
    }
}
