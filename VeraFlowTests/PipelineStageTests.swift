import Foundation
import Testing
@testable import VeraFlow

struct PipelineStageTests {
    @Test("Every stage round-trips through Codable", arguments: PipelineStage.allCases)
    func codableRoundTrip(stage: PipelineStage) throws {
        let data = try JSONEncoder().encode(stage)
        let decoded = try JSONDecoder().decode(PipelineStage.self, from: data)
        #expect(decoded == stage)
    }

    @Test("Transcript becomes readable once transcription finishes")
    func transcriptAvailability() {
        #expect(!PipelineStage.recorded.hasTranscript)
        #expect(!PipelineStage.transcribing.hasTranscript)
        #expect(PipelineStage.transcribed.hasTranscript)
        #expect(PipelineStage.ready.hasTranscript)
    }

    @Test("Only the active work stages count as processing")
    func processingStages() {
        let processing = PipelineStage.allCases.filter(\.isProcessing)
        #expect(processing == [.transcribing, .diarizing, .summarizing])
    }
}
