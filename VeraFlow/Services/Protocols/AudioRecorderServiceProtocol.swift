import Foundation

/// Delegate or stream updates for live recording (§8)
public struct AudioRecordingMetrics: Sendable {
    public var currentDuration: TimeInterval
    public var powerLevel: Float // 0.0 to 1.0 decibel meter
    public var isInterrupted: Bool
    
    public init(currentDuration: TimeInterval = 0, powerLevel: Float = 0, isInterrupted: Bool = false) {
        self.currentDuration = currentDuration
        self.powerLevel = powerLevel
        self.isInterrupted = isInterrupted
    }
}

public protocol AudioRecorderServiceProtocol: Sendable {
    var isRecording: Bool { get async }
    var isPaused: Bool { get async }
    var currentDuration: TimeInterval { get async }
    
    func startRecording(targetDirectory: URL) async throws -> URL
    func pauseRecording() async throws
    func resumeRecording() async throws
    func stopRecording() async throws -> (fileURL: URL, duration: TimeInterval)
    func addBookmark(note: String?) async -> Bookmark
    
    func metricsStream() -> AsyncStream<AudioRecordingMetrics>
}
