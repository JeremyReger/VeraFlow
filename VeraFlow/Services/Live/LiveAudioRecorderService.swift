import AVFAudio
import Foundation
import os

/// Records the microphone to a crash-safe AAC ADTS stream (mono, 44.1 kHz, ~64 kbps) with
/// `AVAudioEngine` (SPEC §8). ADTS instead of CAF because CAF/AAC needs a packet table that is
/// only written on close, so a force-quit left an unreadable file (docs/DECISIONS.md).
/// Handles interruptions, route changes, and disk space. The session and input-device calls
/// go through `RecorderPlatform` (`AVAudioSession` on iOS, Core Audio on the Mac).
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
    /// Format and bound device the current tap was installed against, so a configuration change
    /// that moved neither is recognised as our own (v1.1 plan item 15; see `CaptureRestart`).
    private var tappedCapture: CaptureState?
    /// The port UID the user wants (`nil` = let the system choose). Applied after every activation:
    /// iOS ignores `setPreferredInput` on an inactive session.
    private var wantedInputID: String?
    /// The input the current engine was built with (the Mac binds the device to the engine, so
    /// there is no session preference to read back).
    private var appliedInputID: String?
    /// Set when the input changed while paused on a platform where only a rebuilt engine picks
    /// it up; `resume()` then restarts capture instead of just un-pausing the writer.
    private var inputChangePending = false

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
        switch RecorderPlatform.microphoneAuthorization {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await RecorderPlatform.requestMicrophoneAccess()
        }
    }

    func start(to fileURL: URL) async throws {
        guard status == .idle else { throw AudioRecorderError.alreadyRecording }
        guard RecorderPlatform.microphoneAuthorization == .granted else {
            throw AudioRecorderError.permissionDenied
        }
        if DiskSpacePolicy.evaluate(availableBytes: capacityProvider()) == .stop {
            throw AudioRecorderError.diskFull
        }

        do {
            try RecorderPlatform.activate()
        } catch {
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }
        await applyWantedInput()

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
        writer.previewSink = pendingPreviewSink

        let engine = AVAudioEngine()
        do {
            try RecorderPlatform.applyInput(wantedInputID, to: engine)
            appliedInputID = wantedInputID
        } catch {
            writer.close()
            RecorderPlatform.deactivate()
            throw error
        }
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        Self.log.info("start: input \(inputFormat.sampleRate, privacy: .public) Hz \(inputFormat.channelCount, privacy: .public) ch; route \(RecorderPlatform.routeDescription, privacy: .public)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            writer.close()
            RecorderPlatform.deactivate()
            throw AudioRecorderError.sessionFailed("No microphone is available")
        }

        do {
            try Self.installInputTap(on: engine, inputFormat: inputFormat, recordFormat: recordFormat, writer: writer)
        } catch {
            writer.close()
            RecorderPlatform.deactivate()
            throw error
        }
        tappedCapture = Self.captureState(of: engine, tappedWith: inputFormat)

        engine.prepare()
        do {
            try engine.start()
            Self.log.info("engine running; file \(file.fileFormat.description, privacy: .public); processing \(file.processingFormat.description, privacy: .public)")
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            writer.close()
            RecorderPlatform.deactivate()
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

    /// Pause keeps the engine running and just stops writing: with audio I/O still active iOS
    /// keeps the app alive, so Resume from the Lock Screen works (a backgrounded app may not
    /// *start* recording, only continue it). The mic indicator stays on while paused.
    func pause() async throws {
        guard status == .recording, let writer else { throw AudioRecorderError.notRecording }
        writer.isPaused = true
        status = .paused
        publishSnapshot()
    }

    func resume() async throws {
        guard status == .paused, let writer, let recordFormat else { throw AudioRecorderError.notRecording }
        if let engine, engine.isRunning, !engineNeedsRebuild, !inputChangePending {
            writer.isPaused = false
        } else {
            // The engine stopped (interruption, route change, media reset), or the Mac's input
            // changed while paused: rebuild it.
            try await restartCaptureRetrying(writer: writer, recordFormat: recordFormat)
            writer.isPaused = false
        }
        status = .recording
        publishSnapshot()
    }

    /// Stored on the writer so it is attached before and after every capture restart. A sink set
    /// before `start` is kept for the next recording.
    func setPreviewSink(_ sink: AudioBufferSink?) async {
        pendingPreviewSink = sink
        writer?.previewSink = sink
    }

    private var pendingPreviewSink: AudioBufferSink?

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
        RecorderPlatform.deactivate()

        let result = RecorderResult(fileURL: fileURL, duration: writer.elapsed)
        let writeError = writer.firstWriteError
        let peak = writer.maxPeak
        tearDown()
        status = .idle
        publishSnapshot()
        // Nothing reached the file. Say so now: the alternative is a 0-byte file that only
        // fails later, in the transcription step, as a Core Audio error number.
        guard result.duration > 0 else {
            Self.log.error("stop: no audio written to \(fileURL.lastPathComponent, privacy: .public); peak \(peak, format: .fixed(precision: 3), privacy: .public); first write error \(writeError ?? "none", privacy: .public)")
            throw AudioRecorderError.noAudioCaptured(writeError)
        }
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
        // Inputs are only listed for record-capable categories. Never re-set the category while
        // capture is running; the session is already configured then.
        if status == .idle {
            RecorderPlatform.configureForInputListing()
        }
        return RecorderPlatform.availableInputs()
    }

    /// Remembers the choice. While idle it is only validated; the session is inactive then and
    /// iOS would ignore `setPreferredInput`, so `start()` applies it right after activating.
    /// While recording it takes effect now; on iOS the engine's configuration-change notification
    /// then re-taps the mic in the new route's format, and the Mac rebuilds the engine here.
    func selectInput(id: String?) async throws {
        if status == .idle {
            RecorderPlatform.configureForInputListing()
        }
        // Never refuse a choice: right after a route change the list can be missing a port for
        // a moment (on device the phone mic vanished briefly after switching to Bluetooth), and
        // `applyWantedInput` waits for it. A port that never returns is simply not applied.
        wantedInputID = id
        guard status != .idle else { return }
        await applyWantedInput()
        guard RecorderPlatform.inputChangeNeedsRestart, appliedInputID != wantedInputID else { return }
        if status == .recording, !isRestarting, let writer, let recordFormat {
            try await restartCaptureRetrying(writer: writer, recordFormat: recordFormat)
        } else if status == .paused {
            inputChangePending = true
        }
    }

    /// Applies `wantedInputID` to an *active* session and waits briefly for the route to follow,
    /// so the engine built next taps the mic in the right format.
    private func applyWantedInput() async {
        var available = RecorderPlatform.availableInputs().map(\.id)
        var action = AudioInputRouting.action(
            wanted: wantedInputID,
            available: available,
            sessionPreferred: RecorderPlatform.preferredInputID(applied: appliedInputID)
        )
        // The input list settles a moment after a route change; wait up to a second for the port.
        var settleAttempts = 0
        while case .unavailable = action, settleAttempts < 10 {
            settleAttempts += 1
            try? await Task.sleep(for: .milliseconds(100))
            available = RecorderPlatform.availableInputs().map(\.id)
            action = AudioInputRouting.action(
                wanted: wantedInputID,
                available: available,
                sessionPreferred: RecorderPlatform.preferredInputID(applied: appliedInputID)
            )
        }
        do {
            switch action {
            case .unchanged:
                Self.log.info("input \(self.wantedInputID ?? "automatic", privacy: .public) already preferred; route \(RecorderPlatform.routeDescription, privacy: .public)")
                return
            case .unavailable:
                Self.log.info("input \(self.wantedInputID ?? "-", privacy: .public) not listed after \(settleAttempts, privacy: .public) checks; keeping \(RecorderPlatform.routeDescription, privacy: .public)")
                return
            case .clear:
                try RecorderPlatform.setPreferredInput(nil)
            case .prefer(let id):
                try RecorderPlatform.setPreferredInput(id)
            }
        } catch {
            Self.log.error("setPreferredInput failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        // The route change is asynchronous; give it up to a second before reading the input format.
        if case .prefer(let id) = action {
            await RecorderPlatform.waitForRoute(input: id)
        }
        Self.log.info("input preference applied (\(String(describing: action), privacy: .public)); route \(RecorderPlatform.routeDescription, privacy: .public)")
    }

    // MARK: Interruptions, route changes, engine restarts (SPEC §8.3)

    private func installObservers(for engine: AVAudioEngine) {
        let center = NotificationCenter.default

        observers += RecorderPlatform.observeSession { [weak self] event in
            Task { await self?.handleSessionEvent(event) }
        }

        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.handleConfigurationChange() }
        })
    }

    private func handleSessionEvent(_ event: RecorderSessionEvent) {
        switch event {
        case .interruptionBegan(let reason):
            Self.log.info("interruption began (reason \(reason, privacy: .public)) at \(self.writer?.elapsed ?? 0, format: .fixed(precision: 1), privacy: .public)s")
            guard status == .recording, let engine else { return }
            engine.pause()
            status = .paused
            publishSnapshot()
            emit(.began)
        case .interruptionEnded(let shouldResume):
            Self.log.info("interruption ended; shouldResume \(shouldResume, privacy: .public)")
            guard status == .paused else { return }
            emit(.ended(shouldResume: shouldResume))
        case .mediaServicesReset:
            handleMediaServicesReset()
        case .routeChanged(let oldDeviceUnavailable):
            handleRouteChange(oldDeviceUnavailable: oldDeviceUnavailable)
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

    private func handleRouteChange(oldDeviceUnavailable: Bool) {
        guard status != .idle else { return }
        if oldDeviceUnavailable {
            emit(.routeChanged)
        }
    }

    /// The engine stops itself when the input hardware changes; re-tap the input in its new format.
    /// While paused nothing happens here: `resume()` always re-taps, so the change is picked up then.
    /// What the engine reports about its input right now, next to what the tap was built for.
    private static func captureState(of engine: AVAudioEngine, tappedWith format: AVAudioFormat) -> CaptureState {
        CaptureState(
            sampleRate: format.sampleRate,
            channels: UInt32(format.channelCount),
            deviceID: RecorderPlatform.boundInputDevice(of: engine)
        )
    }

    private static func currentCaptureState(of engine: AVAudioEngine) -> CaptureState {
        captureState(of: engine, tappedWith: engine.inputNode.outputFormat(forBus: 0))
    }

    private func handleConfigurationChange() async {
        guard status == .recording, !isRestarting, let writer, let recordFormat else { return }
        Self.log.info("configuration change while recording")
        // Binding an input device posts one of these itself, so rebuilding the engine for every
        // change binds the device again and posts another. That loop emptied the first Mac
        // recordings: the engine restarted hundreds of times and never delivered a buffer.
        // Rebuild only when the format or the device actually moved.
        if let engine, let tapped = tappedCapture,
           CaptureRestart.decide(tapped: tapped, current: Self.currentCaptureState(of: engine)) == .keepTap {
            if engine.isRunning {
                Self.log.info("configuration change moved nothing; keeping the tap")
                return
            }
            do {
                try engine.start()
                Self.log.info("configuration change moved nothing; restarted the same engine")
                return
            } catch {
                Self.log.error("the same engine would not start again: \(error.localizedDescription, privacy: .public); rebuilding")
            }
        }
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
        do {
            try RecorderPlatform.activate()
            if case .prefer(let id) = AudioInputRouting.action(
                wanted: wantedInputID,
                available: RecorderPlatform.availableInputs().map(\.id),
                sessionPreferred: RecorderPlatform.preferredInputID(applied: appliedInputID)
            ) {
                // Re-assert after an interruption or reset; a later route change re-taps via the
                // configuration-change observer.
                try RecorderPlatform.setPreferredInput(id)
            }
        } catch {
            throw AudioRecorderError.sessionFailed(error.localizedDescription)
        }

        if let old = self.engine, !engineNeedsRebuild {
            old.inputNode.removeTap(onBus: 0)
            old.stop()
        }
        engineNeedsRebuild = false
        inputChangePending = false
        let engine = AVAudioEngine()
        self.engine = engine
        removeObservers()
        installObservers(for: engine)
        // The Mac binds the chosen device to the fresh engine; a device that vanished falls
        // back to the system default rather than failing the restart.
        do {
            try RecorderPlatform.applyInput(wantedInputID, to: engine)
            appliedInputID = wantedInputID
        } catch {
            Self.log.error("could not bind the input device: \(error.localizedDescription, privacy: .public)")
            appliedInputID = nil
        }

        // The tap must use the node's *output* format (Apple's pattern). The hardware format is
        // logged only: after a Bluetooth switch the session can run at the headset's rate while the
        // hardware already reports the iPhone mic's, and that is fine; the converter handles either.
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let hardwareFormat = engine.inputNode.inputFormat(forBus: 0)
        Self.log.info("restart: tap \(inputFormat.sampleRate, privacy: .public) Hz \(inputFormat.channelCount, privacy: .public) ch; hardware \(hardwareFormat.sampleRate, privacy: .public) Hz \(hardwareFormat.channelCount, privacy: .public) ch; route \(RecorderPlatform.routeDescription, privacy: .public)")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw InputFormatSettling()
        }
        try Self.installInputTap(on: engine, inputFormat: inputFormat, recordFormat: recordFormat, writer: writer)
        tappedCapture = Self.captureState(of: engine, tappedWith: inputFormat)
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
        // A live meter with nothing written means the buffers arrive but the file rejects them.
        if let writeError = writer.firstWriteError {
            Self.log.error("recording: the file is rejecting audio: \(writeError, privacy: .public)")
        }
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
        inputChangePending = false
        appliedInputID = nil
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
    /// The first `AVAudioFile.write` failure, kept so a file that rejects every buffer is
    /// reported instead of passing for a silent recording. Later failures are the same one.
    private var _firstWriteError: String?
    private var _isPaused = false
    private var _previewSink: AudioBufferSink?

    init(file: AVAudioFile, sampleRate: Double) {
        self.file = file
        self.sampleRate = sampleRate
    }

    /// While paused, buffers are dropped: the file, the elapsed time, and the meter stand still.
    var isPaused: Bool {
        get { lock.withLock { _isPaused } }
        set {
            lock.withLock {
                _isPaused = newValue
                if newValue { peak = 0 }
            }
        }
    }

    /// The live transcript preview's consumer (v1.1 plan item 4); survives capture restarts
    /// because the writer does.
    var previewSink: AudioBufferSink? {
        get { lock.withLock { _previewSink } }
        set { lock.withLock { _previewSink = newValue } }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        if isPaused { return }
        previewSink?(buffer)
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
            if _firstWriteError == nil { _firstWriteError = error.localizedDescription }
        }
        peak = bufferPeak
        largestPeak = max(largestPeak, bufferPeak)
    }

    /// The first write failure, or nil if every buffer went in.
    var firstWriteError: String? {
        lock.lock()
        defer { lock.unlock() }
        return _firstWriteError
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
