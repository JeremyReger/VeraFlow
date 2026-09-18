import Foundation
import Testing
@testable import VeraFlow

struct PipelineTimelineTests {
    private let id = UUID()
    private let base = Date(timeIntervalSince1970: 1_789_000_000)

    private func entry(_ seconds: TimeInterval, _ event: PipelineEvent) -> PipelineTimeline.Entry {
        PipelineTimeline.Entry(date: base.addingTimeInterval(seconds), event: event)
    }

    @Test("Stage durations come from consecutive stage changes; failures close the stage as failed")
    func timings() {
        let entries = [
            entry(0, .stageChanged(recordingID: id, stage: .transcribing)),
            entry(1, .progress(recordingID: id, stage: .transcribing, fraction: 0.5)),
            entry(12, .stageChanged(recordingID: id, stage: .transcribed)),
            entry(12.5, .stageChanged(recordingID: id, stage: .diarizing)),
            entry(20, .failed(recordingID: id, stage: .diarizing, message: "x")),
            entry(20, .stageChanged(recordingID: id, stage: .diarized)),
            entry(21, .stageChanged(recordingID: id, stage: .summarizing)),
        ]
        let timings = PipelineTimeline.timings(from: entries)
        #expect(timings.map(\.stage) == [.transcribing, .diarizing])
        #expect(timings[0].seconds == 12)
        #expect(timings[0].succeeded)
        #expect(timings[1].seconds == 7.5)
        #expect(!timings[1].succeeded)
        #expect(timings.allSatisfy { $0.recordingID == id })
    }

    @Test("An expired stage that goes back to a waiting stage still records its time")
    func expiry() {
        let timings = PipelineTimeline.timings(from: [
            entry(0, .stageChanged(recordingID: id, stage: .transcribing)),
            entry(30, .stageChanged(recordingID: id, stage: .recorded)),
        ])
        #expect(timings.count == 1)
        #expect(timings[0].seconds == 30)
    }

    @Test("Event descriptions are short and name the stage")
    func describe() {
        #expect(PipelineTimeline.describe(.stageChanged(recordingID: id, stage: .ready)).hasSuffix("→ Ready"))
        #expect(PipelineTimeline.describe(.failed(recordingID: id, stage: .transcribing, message: "boom")).contains("Transcribing failed: boom"))
        #expect(PipelineTimeline.describe(.preparingAssets(recordingID: id, stage: .diarizing, fraction: 0.5)).contains("50%"))
    }
}
