import AVFAudio
import Foundation
import os

/// Records the microphone to a crash-safe AAC ADTS stream (mono, 44.1 kHz, ~64 kbps) with
/// `AVAudioEngine` (SPEC §8). ADTS instead of CAF because CAF/AAC needs a packet table that is
/// only written on close, so a force-quit left an unreadable file (docs/DECISIONS.md).
/// Handles interruptions, route changes, and disk space.
///
/// The graph is just a tap on the input node (no output path); each buffer is converted to the
/// recording format with `AVAudioConverter` before it is written. Uses the classic
/// `installTap`/interruption-notification APIs because the iOS 27 replacements aren't in the
/// iOS 26 SDK (see docs/DECISIONS.md).
actor LiveAudioRecorderService: AudioRecorderService {
    /// Reads free disk space in bytes; injected so tests can drive the thresholds.
    typealias CapacityProvider = @Sendable () -> Int64?

    static let sampleRate: Double = 44_100
    static let bitRate = 64_000

    private static let log = Logger(subsystem: "com.jeremyreger.veraflow", category: "recorder")

    private let capacityProvider: CapacityProvider
    private let diskCheckInterval: Duration

    private var engine: AVAudioEngine?
    private var writer: TapWriter?
    private var recordFormat: AVAudioFormat?
    private var status: RecorderSnapshot.Status = .idle
    private var fileURL: URL?
    private var didWarnLowDisk = false
    /// Set after a media-services reset: the old engine is dead and `resume()` must build a new one.
    private var engineNeedsRebuild = false
    /// True while `restartCapture(retrying:)` is mid-retry, so overlapping configuration-change
    /// notifications don't start a second restart.
    private var isRestarting = false

    /// Thrown by `restartCapture` when the input node reports no usable format yet (0 Hz or 0
    /// channels), which happens for a moment while a route change settles. Retried, never shown.
    private struct InputFormatSettling: Error {}

    private var meterTask: Task<Void, Never>?
    private var diskTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    private var snapshotContinuations: [UUID: AsyncStream<RecorderSnapshot>.Continuation] = [:]
    private var interruptionContinuations: [UUID: AsyncStream<RecorderInterruption>.Continuation] = [:]

    init(capacityProvider: @escaping CapacityProvider, diskCheckInterval: Duration = .seconds(10)) {
        self.capacityProvider = capacityProvider
        self.diskCheckInterval = diskCheckInterval
    }

    // MARK: AudioRecorderService

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await Self.askForRecordPermission()
        @unknown default:
            return await Self.askForRecordPermission()
        }
    }

    private static func askForRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(to fileURL: URL) async throws {
        guard status == .idle else { throw AudioRecorderError.alreadyRecording }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw AudioRecorderError.permissionDenied
        }
        if DiskSpacePolicy.evaluate(availableBytes: capacityProvider()) == .stop {
            throw AudioRecorderError.diskFull
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try Self.configureSession(session)
            try session.setActive(true)
        } catch {
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }

        guard let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.sessionFailed("Could not create the recording format")
        }

        // The container comes from the URL's extension: ".aac" → ADTS, which stays readable when
        // writing is cut off. Callers pass the URL from `RecordingStorage`.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: Self.bitRate,
        ]
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioRecorderError.sessionFailed("Could not create the audio file: \(error.localizedDescription)")
        }
        let writer = TapWriter(file: file, sampleRate: Self.sampleRate)

        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        Self.log.info("start: input \(inputFormat.sampleRate, privacy: .public) Hz \(inputFormat.channelCount, privacy: .public) ch; route \(session.currentRoute.inputs.map(\.portName).joined(separator: ","), privacy: .public) -> \(session.currentRoute.outputs.map(\.portName).joined(separator: ","), privacy: .public)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioRecorderError.sessionFailed("No microphone is available")
        }

        do {
            try Self.installInputTap(on: engine, inputFormat: inputFormat, recordFormat: recordFormat, writer: writer)
        } catch {
            writer.close()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        engine.prepare()
        do {
            try engine.start()
            Self.log.info("engine running; file \(file.fileFormat.description, privacy: .public); processing \(file.processingFormat.description, privacy: .public)")
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            writer.close()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioRecorderError.sessionFailed("Could not start the audio engine: \(error.localizedDescription)")
        }

        self.engine = engine
        self.writer = writer
        self.recordFormat = recordFormat
        self.fileURL = fileURL
        self.didWarnLowDisk = false
        status = .recording
        publishSnapshot()

        installObservers(for: engine)
        startMeter()
        startDiskWatch()
    }

    func pause() async throws {
        guard status == .recording else { throw AudioRecorderError.notRecording }
        engine?.pause()
        status = .paused
        publishSnapshot()
    }

    func resume() async throws {
        guard status == .paused, let writer, let recordFormat else { throw AudioRecorderError.notRecording }
        try await restartCaptureRetrying(writer: writer, recordFormat: recordFormat)
        status = .recording
        publishSnapshot()
    }

    func stop() async throws -> RecorderResult {
        guard status != .idle, let writer, let fileURL else {
            throw AudioRecorderError.notRecording
        }
        // After a media-services reset the old engine is an orphan; leave it alone.
        if let engine, !engineNeedsRebuild {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        writer.close()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        let result = RecorderResult(fileURL: fileURL, duration: writer.elapsed)
        tearDown()
        status = .idle
        publishSnapshot()
        return result
    }

    func currentTime() async -> TimeInterval {
        writer?.elapsed ?? 0
    }

    func snapshots() async -> AsyncStream<RecorderSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RecorderSnapshot>.makeStream()
        snapshotContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotContinuation(id) }
        }
        continuation.yield(currentSnapshot())
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

    func availableInputs() async -> [AudioInputOption] {
        let session = AVAudioSession.sharedInstance()
        // Inputs are only listed for record-capable categories.
        try? Self.configureSession(session)
        return (session.availableInputs ?? []).map { port in
            AudioInputOption(id: port.uid, name: port.portName, isBuiltIn: port.portType == .builtInMic)
        }
    }

    func selectInput(id: String?) async throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try Self.configureSession(session)
            guard let id else {
                try session.setPreferredInput(nil)
                return
            }
            guard let port = session.availableInputs?.first(where: { $0.uid == id }) else {
                throw AudioRecorderError.sessionFailed("That microphone is no longer available")
            }
            try session.setPreferredInput(port)
        } catch let error as AudioRecorderError {
            throw error
        } catch {
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }
    }

    // MARK: Session

    private static func configureSession(_ session: AVAudioSession) throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
    }

    // MARK: Interruptions, route changes, engine restarts (SPEC §8.3)

    private func installObservers(for engine: AVAudioEngine) {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
            let rawReason = notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            Task { await self?.handleInterruption(type, shouldResume: shouldResume, rawReason: rawReason) }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleMediaServicesReset() }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: nil
        ) { [weak self] notification in
            guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
            Task { await self?.handleRouteChange(reason) }
        })

        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleConfigurationChange() }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool, rawReason: UInt?) {
        switch type {
        case .began:
            Self.log.info("interruption began (reason \(Self.describeInterruptionReason(rawReason), privacy: .public)) at \(self.writer?.elapsed ?? 0, format: .fixed(precision: 1), privacy: .public)s")
            guard status == .recording, let engine else { return }
            engine.pause()
            status = .paused
            publishSnapshot()
            emit(.began)
        case .ended:
            Self.log.info("interruption ended; shouldResume \(shouldResume, privacy: .public)")
            guard status == .paused else { return }
            emit(.ended(shouldResume: shouldResume))
        @unknown default:
            break
        }
    }

    /// Why the system interrupted us, for the device log (SPEC §8.3 troubleshooting).
    private static func describeInterruptionReason(_ rawReason: UInt?) -> String {
        guard let rawReason else { return "none" }
        switch AVAudioSession.InterruptionReason(rawValue: rawReason) {
        case .default?: return "default (call, alarm, Siri, or another app)"
        case .builtInMicMuted?: return "built-in mic muted"
        case .routeDisconnected?: return "route disconnected"
        default: return "raw \(rawReason)"
        }
    }

    /// The media server restarted underneath us: every engine and session object is now invalid.
    /// Treat it like an interruption; `resume()` builds a fresh engine.
    private func handleMediaServicesReset() {
        guard status != .idle else { return }
        Self.log.error("media services were reset at \(self.writer?.elapsed ?? 0, format: .fixed(precision: 1), privacy: .public)s; engine will be rebuilt on resume")
        engineNeedsRebuild = true
        guard status == .recording else { return }
        status = .paused
        publishSnapshot()
        emit(.began)
        emit(.ended(shouldResume: true))
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        guard status != .idle else { return }
        if reason == .oldDeviceUnavailable {
            emit(.routeChanged)
        }
    }

    /// The engine stops itself when the input hardware changes; re-tap the input in its new format.
    /// While paused nothing happens here: `resume()` always re-taps, so the change is picked up then.
    private func handleConfigurationChange() async {
        guard status == .recording, !isRestarting, let writer, let recordFormat else { return }
        Self.log.info("configuration change while recording")
        do {
            try await restartCaptureRetrying(writer: writer, recordFormat: recordFormat)
        } catch {
            Self.log.error("could not resume after configuration change: \(error.localizedDescription, privacy: .public)")
            status = .paused
            publishSnapshot()
            emit(.began)
            emit(.ended(shouldResume: false))
        }
    }

    /// `restartCapture` with a few short retries while the mic's format settles after a route change.
    private func restartCaptureRetrying(writer: TapWriter, recordFormat: AVAudioFormat) async throws {
        isRestarting = true
        defer { isRestarting = false }
        let attempts = 6
        for attempt in 1...attempts {
            do {
                try restartCapture(writer: writer, recordFormat: recordFormat)
                return
            } catch is InputFormatSettling {
                Self.log.info("restart attempt \(attempt, privacy: .public): input format still settling")
                if attempt < attempts {
                    try? await Task.sleep(for: .milliseconds(250))
                    // Stop may have run while we slept.
                    guard status != .idle else { throw AudioRecorderError.notRecording }
                }
            }
        }
        throw AudioRecorderError.sessionFailed("No microphone is available right now. Try Resume again.")
    }

    /// Discards the engine, builds a new one, installs a tap against the microphone's *current*
    /// format, and starts it. Always a fresh engine: on device, after earbuds disconnected, the
    /// old engine's input node kept reporting the earbuds' 16 kHz while the hardware was already
    /// the iPhone mic at 48 kHz, and a tap in a stale format is what `installTap` raises an
    /// uncatchable Objective-C exception for (the 90-minute-test crash). Everything is checked
    /// before that call so a bad state degrades to "Paused" instead. The writer keeps the same
    /// file, so the recording is continuous across restarts. After a media-services reset the old
    /// engine is an orphan and is not touched.
    private func restartCapture(writer: TapWriter, recordFormat: AVAudioFormat) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try Self.configureSession(session)
            try session.setActive(true)
        } catch {
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }

        if let old = self.engine, !engineNeedsRebuild {
            old.inputNode.removeTap(onBus: 0)
            old.stop()
        }
        engineNeedsRebuild = false
        let engine = AVAudioEngine()
        self.engine = engine
        removeObservers()
        installObservers(for: engine)

        // The tap must use the node's *output* format (Apple's pattern). The hardware format is
        // logged only: after a Bluetooth switch the session can run at the headset's rate while the
        // hardware already reports the iPhone mic's, and that is fine; the converter handles either.
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let hardwareFormat = engine.inputNode.inputFormat(forBus: 0)
        Self.log.info("restart: tap \(inputFormat.sampleRate, privacy: .public) Hz \(inputFormat.channelCount, privacy: .public) ch; hardware \(hardwareFormat.sampleRate, privacy: .public) Hz \(hardwareFormat.channelCount, privacy: .public) ch; route \(session.currentRoute.inputs.map(\.portName).joined(separator: ","), privacy: .public)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw InputFormatSettling()
        }
        try Self.installInputTap(on: engine, inputFormat: inputFormat, recordFormat: recordFormat, writer: writer)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.sessionFailed("Could not restart the audio engine: \(error.localizedDescription)")
        }
    }

    /// Taps the mic in its native format and converts each buffer to `recordFormat` for the writer.
    private static func installInputTap(
        on engine: AVAudioEngine,
        inputFormat: AVAudioFormat,
        recordFormat: AVAudioFormat,
        writer: TapWriter
    ) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: recordFormat) else {
            throw AudioRecorderError.sessionFailed("Could not convert \(inputFormat) to the recording format")
        }
        let resampler = BufferResampler(converter: converter, outputFormat: recordFormat)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            if let converted = resampler.convert(buffer) {
                writer.append(converted)
            }
        }
    }

    // MARK: Meter and disk watch

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task.detached { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                await self.publishSnapshot()
                ticks += 1
                if ticks % 50 == 0 {
                    await self.logProgress()
                }
            }
        }
    }

    private func logProgress() {
        guard let writer else { return }
        Self.log.info("recording: \(writer.elapsed, format: .fixed(precision: 1), privacy: .public)s written, level \(writer.level, format: .fixed(precision: 2), privacy: .public), peak so far \(writer.maxPeak, format: .fixed(precision: 3), privacy: .public)")
    }

    private func startDiskWatch() {
        diskTask?.cancel()
        let interval = diskCheckInterval
        diskTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                await self.checkDiskSpace()
            }
        }
    }

    private func checkDiskSpace() {
        guard status != .idle else { return }
        let available = capacityProvider()
        switch DiskSpacePolicy.evaluate(availableBytes: available) {
        case .ok:
            break
        case .warn:
            if !didWarnLowDisk {
                didWarnLowDisk = true
                emit(.lowDiskSpace(availableBytes: available ?? 0))
            }
        case .stop:
            if status == .recording, let engine {
                engine.pause()
                status = .paused
                publishSnapshot()
            }
            emit(.diskFull(availableBytes: available ?? 0))
        }
    }

    // MARK: Publishing

    private func currentSnapshot() -> RecorderSnapshot {
        RecorderSnapshot(
            status: status,
            elapsed: writer?.elapsed ?? 0,
            level: status == .recording ? (writer?.level ?? 0) : 0
        )
    }

    private func publishSnapshot() {
        let snapshot = currentSnapshot()
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    private func emit(_ interruption: RecorderInterruption) {
        for continuation in interruptionContinuations.values {
            continuation.yield(interruption)
        }
    }

    private func tearDown() {
        meterTask?.cancel()
        meterTask = nil
        diskTask?.cancel()
        diskTask = nil
        removeObservers()
        engine = nil
        engineNeedsRebuild = false
        writer = nil
        recordFormat = nil
        fileURL = nil
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func removeSnapshotContinuation(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func removeInterruptionContinuation(_ id: UUID) {
        interruptionContinuations[id] = nil
    }
}

/// Converts input-node buffers (any rate/channel count) to the recording format, one buffer at a time.
/// Owned by a single tap block, so it is only ever used from the audio render thread.
private final class BufferResampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    init(converter: AVAudioConverter, outputFormat: AVAudioFormat) {
        self.converter = converter
        self.outputFormat = outputFormat
        self.ratio = outputFormat.sampleRate / converter.inputFormat.sampleRate
    }

    func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let pending = PendingInput(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if let buffer = pending.take() {
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        switch status {
        case .haveData, .inputRanDry:
            return output.frameLength > 0 ? output : nil
        case .endOfStream, .error:
            return nil
        @unknown default:
            return nil
        }
    }
}

/// Hands one input buffer to an `AVAudioConverter` input block exactly once. The block is
/// `@Sendable`, so the buffer travels in this box; it is only touched on the render thread.
private final class PendingInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

/// Writes tap buffers to the file and tracks frames written and peak level.
/// Called from the audio render thread; guarded by a lock so the actor can read it.
private final class TapWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let sampleRate: Double
    private let lock = NSLock()
    private var framesWritten: AVAudioFramePosition = 0
    private var peak: Float = 0
    private var largestPeak: Float = 0
    private var isClosed = false

    init(file: AVAudioFile, sampleRate: Double) {
        self.file = file
        self.sampleRate = sampleRate
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        var bufferPeak: Float = 0
        if let channels = buffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = UnsafeBufferPointer(start: channels[channel], count: frameCount)
                for sample in samples {
                    bufferPeak = max(bufferPeak, abs(sample))
                }
            }
        }
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        do {
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
        } catch {
            // Keep going; the next buffer may succeed. Disk-full is caught by the disk watch.
        }
        peak = bufferPeak
        largestPeak = max(largestPeak, bufferPeak)
    }

    /// Largest sample seen since start; 0 means the file is silent.
    var maxPeak: Float {
        lock.lock()
        defer { lock.unlock() }
        return largestPeak
    }

    /// Seconds of audio written so far. Paused time never reaches the tap, so it's excluded.
    var elapsed: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return TimeInterval(framesWritten) / sampleRate
    }

    /// Meter value 0...1 for the most recent buffer.
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return AudioLevel.normalized(peak: peak)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        isClosed = true
        file.close()
    }
}
