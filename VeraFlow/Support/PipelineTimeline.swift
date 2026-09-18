import Foundation

/// Turns the pipeline's event log into per-stage timings for Diagnostics (SPEC §15).
enum PipelineTimeline {
    struct Entry: Equatable, Sendable, Identifiable {
        var date: Date
        var event: PipelineEvent
        var id: Date { date }
    }

    struct StageTiming: Equatable, Sendable, Identifiable {
        var recordingID: UUID
        var stage: PipelineStage
        var seconds: TimeInterval
        var succeeded: Bool
        var id: String { "\(recordingID.uuidString)-\(stage.rawValue)-\(seconds)" }
    }

    /// One timing per processing stage that started and then ended (next stage, failure, or the
    /// recording going back to a waiting stage). Stages still running are left out.
    static func timings(from entries: [Entry]) -> [StageTiming] {
        var open: [UUID: (stage: PipelineStage, start: Date)] = [:]
        var result: [StageTiming] = []
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            switch entry.event {
            case .stageChanged(let id, let stage):
                if let running = open[id], running.stage != stage {
                    result.append(StageTiming(
                        recordingID: id,
                        stage: running.stage,
                        seconds: entry.date.timeIntervalSince(running.start),
                        succeeded: true
                    ))
                    open[id] = nil
                }
                if stage.isProcessing {
                    open[id] = (stage, entry.date)
                }
            case .failed(let id, let stage, _):
                if let running = open[id] {
                    result.append(StageTiming(
                        recordingID: id,
                        stage: stage,
                        seconds: entry.date.timeIntervalSince(running.start),
                        succeeded: false
                    ))
                    open[id] = nil
                }
            case .progress, .preparingAssets, .recoveredInterruptedRecording:
                break
            }
        }
        return result
    }

    /// Short description of an event for the log.
    static func describe(_ event: PipelineEvent) -> String {
        switch event {
        case .stageChanged(let id, let stage):
            return "\(short(id)) → \(stage.displayName)"
        case .progress(let id, let stage, let fraction):
            return "\(short(id)) \(stage.displayName) \(Int(fraction * 100))%"
        case .preparingAssets(let id, let stage, let fraction):
            return "\(short(id)) downloading for \(stage.displayName) \(Int(fraction * 100))%"
        case .failed(let id, let stage, let message):
            return "\(short(id)) \(stage.displayName) failed: \(message)"
        case .recoveredInterruptedRecording(let id):
            return "\(short(id)) recovered after an interrupted recording"
        }
    }

    private static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
