import Foundation

public final class FakeAudioRecorderService: AudioRecorderServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isRecording = false
    private var _isPaused = false
    private var _duration: TimeInterval = 0
    private var bookmarks: [Bookmark] = []
    
    public init() {}
    
    public var isRecording: Bool {
        lock.withLock { _isRecording }
    }
    
    public var isPaused: Bool {
        lock.withLock { _isPaused }
    }
    
    public var currentDuration: TimeInterval {
        lock.withLock { _duration }
    }
    
    public func startRecording(targetDirectory: URL) async throws -> URL {
        lock.withLock {
            _isRecording = true
            _isPaused = false
            _duration = 0
            bookmarks.removeAll()
        }
        return targetDirectory.appendingPathComponent("fake_recording.caf")
    }
    
    public func pauseRecording() async throws {
        lock.withLock { _isPaused = true }
    }
    
    public func resumeRecording() async throws {
        lock.withLock { _isPaused = false }
    }
    
    public func stopRecording() async throws -> (fileURL: URL, duration: TimeInterval) {
        let (duration, _) = lock.withLock { () -> (TimeInterval, Bool) in
            let d = _duration > 0 ? _duration : 120.0
            _isRecording = false
            _isPaused = false
            return (d, true)
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake_recording.caf")
        return (tempURL, duration)
    }
    
    public func addBookmark(note: String?) async -> Bookmark {
        let b = Bookmark(time: lock.withLock { _duration }, note: note)
        lock.withLock { bookmarks.append(b) }
        return b
    }
    
    public func metricsStream() -> AsyncStream<AudioRecordingMetrics> {
        AsyncStream { continuation in
            continuation.yield(AudioRecordingMetrics(currentDuration: 0, powerLevel: 0.5, isInterrupted: false))
            continuation.finish()
        }
    }
}
