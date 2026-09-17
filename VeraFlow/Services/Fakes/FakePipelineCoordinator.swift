import Foundation

public final class FakePipelineCoordinator: PipelineCoordinatorProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedIDs: [UUID] = []
    
    public init() {}
    
    public func enqueue(recordingID: UUID) async {
        lock.withLock { queuedIDs.append(recordingID) }
    }
    
    public func cancel(recordingID: UUID) async {
        lock.withLock { queuedIDs.removeAll { $0 == recordingID } }
    }
    
    public func retry(recordingID: UUID) async {
        await enqueue(recordingID: recordingID)
    }
    
    public func recoverInterruptedRecordings() async {}
    
    public func progressStream() -> AsyncStream<PipelineProgressUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
