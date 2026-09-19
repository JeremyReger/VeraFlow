import AVFAudio
import Foundation

/// Audio handed to the preview from the recorder's tap, on the render thread, already in the
/// recording format (v1.1 plan item 4).
typealias AudioBufferSink = @Sendable (AVAudioPCMBuffer) -> Void

/// What the Record screen shows: the last few finished lines and the line being spoken.
/// Nothing here is persisted; the real transcript comes from the file pass after Stop.
struct PreviewState: Sendable, Equatable {
    /// Finished lines, oldest first, at most `PreviewReducer.historyLimit`.
    var finalized: [String] = []
    /// The line still changing as more audio arrives.
    var volatile: String = ""

    var isEmpty: Bool { finalized.isEmpty && volatile.isEmpty }

    /// What reads as the current line: the volatile text, else the last finished line.
    var currentLine: String { volatile.isEmpty ? (finalized.last ?? "") : volatile }

    /// The line before the current one, dimmed on screen.
    var previousLine: String {
        if volatile.isEmpty {
            return finalized.count >= 2 ? finalized[finalized.count - 2] : ""
        }
        return finalized.last ?? ""
    }
}

enum PreviewEvent: Sendable, Equatable {
    /// Text that may still change.
    case volatile(String)
    /// Text the recognizer has settled on.
    case finalized(String)
}

/// Pure state machine for the preview, so the rules are testable without a microphone.
enum PreviewReducer {
    static let historyLimit = 5

    static func apply(_ event: PreviewEvent, to state: inout PreviewState) {
        switch event {
        case .volatile(let text):
            state.volatile = Self.clean(text)
        case .finalized(let text):
            let line = Self.clean(text)
            state.volatile = ""
            guard !line.isEmpty else { return }
            state.finalized.append(line)
            if state.finalized.count > historyLimit {
                state.finalized.removeFirst(state.finalized.count - historyLimit)
            }
        }
    }

    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A running preview: events to show and the sink the recorder feeds.
struct PreviewSession: Sendable {
    var events: AsyncStream<PreviewEvent>
    var sink: AudioBufferSink
}

enum TranscriptPreviewError: Error, Equatable {
    case unavailable
    case failed(String)
}

/// Words while recording (v1.1 plan item 4). `LiveTranscriptPreview` runs Apple's
/// `SpeechTranscriber` with volatile results; the fake is scripted.
protocol TranscriptPreviewService: Sendable {
    /// True when the on-device transcriber can run for this locale. The dictation fallback is
    /// never used for the preview.
    func isAvailable(locale: Locale) async -> Bool
    /// Starts a session. A session already running is stopped first.
    func start(locale: Locale) async throws -> PreviewSession
    func stop() async
}

/// Scripted preview for tests and previews.
actor FakeTranscriptPreviewService: TranscriptPreviewService {
    var available = true
    var failsToStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var buffersReceived = 0
    private var continuation: AsyncStream<PreviewEvent>.Continuation?

    init(available: Bool = true) {
        self.available = available
    }

    func isAvailable(locale: Locale) async -> Bool { available }

    func start(locale: Locale) async throws -> PreviewSession {
        if failsToStart { throw TranscriptPreviewError.failed("scripted") }
        continuation?.finish()
        startCount += 1
        let (stream, continuation) = AsyncStream<PreviewEvent>.makeStream()
        self.continuation = continuation
        return PreviewSession(events: stream) { [weak self] _ in
            Task { await self?.countBuffer() }
        }
    }

    func stop() async {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    var isRunning: Bool { continuation != nil }

    // MARK: Test controls

    func emit(_ event: PreviewEvent) {
        continuation?.yield(event)
    }

    func setAvailable(_ value: Bool) { available = value }
    func setFailsToStart(_ value: Bool) { failsToStart = value }

    private func countBuffer() { buffersReceived += 1 }
}
