import Foundation

/// Live state of the recorder, published while a recording is in progress.
struct RecorderSnapshot: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case idle
        case recording
        case paused
    }

    var status: Status = .idle
    /// Seconds of audio captured (excludes paused time).
    var elapsed: TimeInterval = 0
    /// Peak input level, 0...1.
    var level: Float = 0
}

/// Why the recorder was interrupted (SPEC §8.3).
enum RecorderInterruption: Sendable, Equatable {
    /// A phone call or other audio session interruption began. The recorder auto-paused.
    case began
    /// The interruption ended. `shouldResume` mirrors the system hint; the UI still asks the user.
    case ended(shouldResume: Bool)
    /// The audio route changed (e.g. a headset disconnected). Recording continues on the built-in mic.
    case routeChanged
    /// Free disk space fell below the warning threshold (SPEC §8.3).
    case lowDiskSpace(availableBytes: Int64)
    /// Free disk space fell below the hard limit. The recorder paused itself; the UI should stop and save.
    case diskFull(availableBytes: Int64)
}

/// A microphone the user can record from (SPEC §8.1).
struct AudioInputOption: Sendable, Identifiable, Hashable {
    /// The audio session port UID.
    var id: String
    var name: String
    var isBuiltIn: Bool
}

/// The result of stopping a recording.
struct RecorderResult: Sendable, Equatable {
    var fileURL: URL
    var duration: TimeInterval
}

enum AudioRecorderError: Error, Equatable {
    case permissionDenied
    case alreadyRecording
    case notRecording
    case diskFull
    case sessionFailed(String)
}

/// Records audio to a crash-safe AAC (ADTS) file (SPEC §8; see docs/DECISIONS.md). Implemented for real in M1.
protocol AudioRecorderService: Sendable {
    /// Asks for microphone permission if needed. Returns whether recording is allowed.
    func requestPermission() async -> Bool
    /// Starts recording to `fileURL`. The file must be inside a `RecordingStorage` folder.
    func start(to fileURL: URL) async throws
    func pause() async throws
    func resume() async throws
    /// Stops and finalizes the file.
    func stop() async throws -> RecorderResult
    /// Current elapsed time; used to timestamp bookmarks.
    func currentTime() async -> TimeInterval
    /// Emits a snapshot whenever the timer, level, or status changes.
    func snapshots() async -> AsyncStream<RecorderSnapshot>
    /// Emits interruptions and route changes.
    func interruptions() async -> AsyncStream<RecorderInterruption>
    /// Microphones currently available (built-in, AirPods, USB...).
    func availableInputs() async -> [AudioInputOption]
    /// Prefers an input for the next and current recording. `nil` lets the system choose.
    func selectInput(id: String?) async throws
}

/// Scripted recorder for tests and previews. Advances time only when told to.
actor FakeAudioRecorderService: AudioRecorderService {
    private(set) var snapshot = RecorderSnapshot()
    private(set) var startedURL: URL?
    private(set) var selectedInputID: String?
    var permissionGranted = true
    var inputs: [AudioInputOption] = [
        AudioInputOption(id: "builtin", name: "iPhone Microphone", isBuiltIn: true),
        AudioInputOption(id: "airpods", name: "AirPods", isBuiltIn: false),
    ]

    private var snapshotContinuations: [UUID: AsyncStream<RecorderSnapshot>.Continuation] = [:]
    private var interruptionContinuations: [UUID: AsyncStream<RecorderInterruption>.Continuation] = [:]

    init(permissionGranted: Bool = true) {
        self.permissionGranted = permissionGranted
    }

    func requestPermission() async -> Bool { permissionGranted }

    func start(to fileURL: URL) async throws {
        guard permissionGranted else { throw AudioRecorderError.permissionDenied }
        guard snapshot.status == .idle else { throw AudioRecorderError.alreadyRecording }
        startedURL = fileURL
        snapshot = RecorderSnapshot(status: .recording, elapsed: 0, level: 0)
        publish()
    }

    func pause() async throws {
        guard snapshot.status == .recording else { throw AudioRecorderError.notRecording }
        snapshot.status = .paused
        publish()
    }

    func resume() async throws {
        guard snapshot.status == .paused else { throw AudioRecorderError.notRecording }
        snapshot.status = .recording
        publish()
    }

    func stop() async throws -> RecorderResult {
        guard snapshot.status != .idle, let url = startedURL else { throw AudioRecorderError.notRecording }
        let result = RecorderResult(fileURL: url, duration: snapshot.elapsed)
        snapshot = RecorderSnapshot()
        startedURL = nil
        publish()
        return result
    }

    func currentTime() async -> TimeInterval { snapshot.elapsed }

    func snapshots() async -> AsyncStream<RecorderSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RecorderSnapshot>.makeStream()
        snapshotContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotContinuation(id) }
        }
        continuation.yield(snapshot)
        return stream
    }

    func interruptions() async -> AsyncStream<RecorderInterruption> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RecorderInterruption>.makeStream()
        interruptionContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeInterruptionContinuation(id) }
        }
        return stream
    }

    func availableInputs() async -> [AudioInputOption] { inputs }

    func selectInput(id: String?) async throws {
        if let id, !inputs.contains(where: { $0.id == id }) {
            throw AudioRecorderError.sessionFailed("Input \(id) is not available")
        }
        selectedInputID = id
    }

    // MARK: Test controls

    /// Pretends `seconds` of audio were captured at `level`.
    func advance(by seconds: TimeInterval, level: Float = 0.5) {
        guard snapshot.status == .recording else { return }
        snapshot.elapsed += seconds
        snapshot.level = level
        publish()
    }

    /// Simulates a system interruption or route change.
    func simulate(_ interruption: RecorderInterruption) {
        switch interruption {
        case .began, .diskFull:
            if snapshot.status == .recording {
                snapshot.status = .paused
                publish()
            }
        default:
            break
        }
        for continuation in interruptionContinuations.values {
            continuation.yield(interruption)
        }
    }

    private func publish() {
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func removeInterruptionContinuation(_ id: UUID) {
        interruptionContinuations[id] = nil
    }
}
