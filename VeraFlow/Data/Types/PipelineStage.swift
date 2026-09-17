import Foundation

/// State machine stages for recording processing pipeline (§6.3)
public enum PipelineStage: String, Codable, Sendable, CaseIterable {
    case recording      // Capture in progress (used for crash recovery)
    case recorded       // Audio captured and finalized
    case transcribing   // SpeechAnalyzer transcription running
    case transcribed    // Timed words generated and initial segments formed
    case diarizing      // FluidAudio speaker diarization running
    case diarized       // Speaker turns aligned with words
    case summarizing    // Foundation Models summary generation running
    case ready          // Fully processed with summary and action items
    case failed         // Error occurred at a stage; non-fatal stages can be retried
    
    public var isTerminal: Bool {
        self == .ready || self == .failed
    }
    
    public var displayTitle: String {
        switch self {
        case .recording: "Recording..."
        case .recorded: "Recorded"
        case .transcribing: "Transcribing..."
        case .transcribed: "Transcribed"
        case .diarizing: "Identifying Speakers..."
        case .diarized: "Speakers Identified"
        case .summarizing: "Summarizing..."
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}
