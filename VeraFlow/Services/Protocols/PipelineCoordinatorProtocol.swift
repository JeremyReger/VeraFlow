import Foundation

public struct PipelineProgressUpdate: Sendable {
    public var recordingID: UUID
    public var stage: PipelineStage
    public var progress: Double // 0.0 to 1.0
    public var statusDescription: String
    
    public init(recordingID: UUID, stage: PipelineStage, progress: Double, statusDescription: String) {
        self.recordingID = recordingID
        self.stage = stage
        self.progress = progress
        self.statusDescription = statusDescription
    }
}

public protocol PipelineCoordinatorProtocol: Sendable {
    func enqueue(recordingID: UUID) async
    func cancel(recordingID: UUID) async
    func retry(recordingID: UUID) async
    func recoverInterruptedRecordings() async
    
    func progressStream() -> AsyncStream<PipelineProgressUpdate>
}
