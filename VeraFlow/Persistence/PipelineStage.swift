import Foundation

/// Processing stage of a recording (SPEC §6.3). Persisted on `Recording`.
enum PipelineStage: String, Codable, Sendable, CaseIterable {
    /// Capture in progress. Used for crash recovery on launch (SPEC §8.2).
    case recording
    case recorded
    case transcribing
    case transcribed
    case diarizing
    case diarized
    case summarizing
    case ready
    /// Processing failed; `Recording.failureMessage` says why.
    case failed

    /// Stages that still have automatic work ahead of them.
    var isProcessing: Bool {
        switch self {
        case .transcribing, .diarizing, .summarizing: true
        default: false
        }
    }

    /// The transcript is available to read from this stage on (SPEC §4.3).
    var hasTranscript: Bool {
        switch self {
        case .transcribed, .diarizing, .diarized, .summarizing, .ready: true
        default: false
        }
    }

    /// Short label for the library row.
    var displayName: String {
        switch self {
        case .recording: "Recording"
        case .recorded: "Waiting to process"
        case .transcribing: "Transcribing"
        case .transcribed: "Transcribed"
        case .diarizing: "Labeling speakers"
        case .diarized: "Speakers labeled"
        case .summarizing: "Summarizing"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}
