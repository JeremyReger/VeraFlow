import Foundation
import AVFoundation
#if os(iOS)
import UIKit
#endif

/// Production implementation of AudioRecorderServiceProtocol (§8)
/// Records crash-safe CAF container with AAC mono 44.1 kHz via AVAudioEngine.
public final class AudioRecorderService: AudioRecorderServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var activeFileURL: URL?
    
    private var _isRecording = false
    private var _isPaused = false
    private var _isInterrupted = false
    private var _currentDuration: TimeInterval = 0
    private var recordedFrameCount: AVAudioFramePosition = 0
    private var sampleRate: Double = AppConstants.sampleRate
    
    private var bookmarks: [Bookmark] = []
    private var metricsContinuations: [UUID: AsyncStream<AudioRecordingMetrics>.Continuation] = [:]
    
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    
    public init() {
        setupSessionObservers()
    }
    
    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        teardownEngine()
    }
    
    // MARK: - Protocol Properties
    
    public var isRecording: Bool {
        lock.withLock { _isRecording }
    }
    
    public var isPaused: Bool {
        lock.withLock { _isPaused }
    }
    
    public var currentDuration: TimeInterval {
        lock.withLock { _currentDuration }
    }
    
    // MARK: - Recording Lifecycle
    
    public func startRecording(targetDirectory: URL) async throws -> URL {
        try lock.withLock {
            if _isRecording {
                throw AudioRecorderError.alreadyRecording
            }
            
            // 1. Ensure target directory exists
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            
            // 2. Check disk space guard (§8.3)
            let freeMB = checkAvailableDiskSpaceMB(for: targetDirectory)
            if freeMB < 100 {
                throw AudioRecorderError.insufficientDiskSpace(freeMB: freeMB)
            }
            
            // 3. Configure Audio Session on iOS (§8.1)
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            
            // 4. Create CAF destination file URL
            let fileName = "recording_\(UUID().uuidString).caf"
            let destinationURL = targetDirectory.appendingPathComponent(fileName)
            
            // 5. Initialize AVAudioEngine and Input Node
            let newEngine = AVAudioEngine()
            let inputNode = newEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            self.sampleRate = inputFormat.sampleRate > 0 ? inputFormat.sampleRate : AppConstants.sampleRate
            
            // 6. Output settings: CAF Container, AAC, Mono, 44.1 kHz, ~64 kbps (§8.2)
            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: AppConstants.sampleRate,
                AVNumberOfChannelsKey: AppConstants.targetChannels,
                AVEncoderBitRateKey: AppConstants.defaultBitRate
            ]
            
            let file = try AVAudioFile(
                forWriting: destinationURL,
                settings: outputSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            
            // 7. Install tap on inputNode
            let bufferSize: AVAudioFrameCount = 4096
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer)
            }
            
            // 8. Start engine
            try newEngine.start()
            
            // 9. Update state
            self.engine = newEngine
            self.audioFile = file
            self.activeFileURL = destinationURL
            self._isRecording = true
            self._isPaused = false
            self._isInterrupted = false
            self._currentDuration = 0
            self.recordedFrameCount = 0
            self.bookmarks.removeAll()
            
            return destinationURL
        }
    }
    
    public func pauseRecording() async throws {
        lock.withLock {
            guard _isRecording, !_isPaused else { return }
            _isPaused = true
            broadcastMetrics(powerLevel: 0)
        }
    }
    
    public func resumeRecording() async throws {
        lock.withLock {
            guard _isRecording, _isPaused else { return }
            _isPaused = false
            _isInterrupted = false
            broadcastMetrics(powerLevel: 0)
        }
    }
    
    public func stopRecording() async throws -> (fileURL: URL, duration: TimeInterval) {
        try lock.withLock {
            guard _isRecording, let fileURL = activeFileURL else {
                throw AudioRecorderError.notRecording
            }
            
            let finalDuration = _currentDuration
            teardownEngine()
            
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            
            _isRecording = false
            _isPaused = false
            _isInterrupted = false
            activeFileURL = nil
            
            broadcastMetrics(powerLevel: 0)
            return (fileURL, finalDuration)
        }
    }
    
    public func addBookmark(note: String?) async -> Bookmark {
        lock.withLock {
            let bookmark = Bookmark(time: _currentDuration, note: note)
            bookmarks.append(bookmark)
            return bookmark
        }
    }
    
    // MARK: - Live Metrics Stream (§4.2, §8)
    
    public func metricsStream() -> AsyncStream<AudioRecordingMetrics> {
        let streamID = UUID()
        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.lock.withLock {
                self.metricsContinuations[streamID] = continuation
                let initial = AudioRecordingMetrics(
                    currentDuration: self._currentDuration,
                    powerLevel: 0,
                    isInterrupted: self._isInterrupted
                )
                continuation.yield(initial)
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    _ = self?.metricsContinuations.removeValue(forKey: streamID)
                }
            }
        }
    }
    
    // MARK: - Real-Time Audio Buffer Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard _isRecording, !_isPaused, let file = audioFile else { return }
            
            // 1. Write buffer to CAF file (real-time compression)
            do {
                try file.write(from: buffer)
                recordedFrameCount += Int64(buffer.frameLength)
                _currentDuration = Double(recordedFrameCount) / sampleRate
            } catch {
                // Non-fatal buffer write skip
            }
            
            // 2. Calculate RMS power level (0.0 to 1.0)
            let powerLevel = calculateRMSPower(from: buffer)
            
            // 3. Broadcast metrics
            broadcastMetrics(powerLevel: powerLevel)
        }
    }
    
    private func calculateRMSPower(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }
        
        var sumSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameLength))
        // Normalize: typical speech RMS is ~0.05 to 0.3
        return min(1.0, max(0.0, rms * 4.5))
    }
    
    private func broadcastMetrics(powerLevel: Float) {
        let metrics = AudioRecordingMetrics(
            currentDuration: _currentDuration,
            powerLevel: powerLevel,
            isInterrupted: _isInterrupted
        )
        for continuation in metricsContinuations.values {
            continuation.yield(metrics)
        }
    }
    
    private func teardownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        audioFile = nil
    }
    
    // MARK: - Interruption & Route Change Handling (§8.3)
    
    private func setupSessionObservers() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
        
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        #endif
    }
    
    #if os(iOS)
    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        lock.withLock {
            switch type {
            case .began:
                guard _isRecording else { return }
                _isPaused = true
                _isInterrupted = true
                let bookmark = Bookmark(time: _currentDuration, note: "Interrupted")
                bookmarks.append(bookmark)
                broadcastMetrics(powerLevel: 0)
                
            case .ended:
                guard _isRecording else { return }
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        // Do not auto-resume silently (§8.3); mark interrupted so UI prompts user
                        _isInterrupted = true
                        broadcastMetrics(powerLevel: 0)
                    }
                }
            @unknown default:
                break
            }
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        // If headset/AirPods disconnects, continue seamlessly on built-in microphone (§8.3)
        if reason == .oldDeviceUnavailable {
            lock.withLock {
                guard _isRecording else { return }
                // Built-in mic fallback is handled automatically by AVAudioEngine playAndRecord category
            }
        }
    }
    #endif
    
    // MARK: - Disk Space Guard (§8.3)
    
    private func checkAvailableDiskSpaceMB(for directory: URL) -> Int64 {
        do {
            let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity / (1024 * 1024)
            }
        } catch {}
        return 1000 // Default fallback if check fails
    }
}

public enum AudioRecorderError: LocalizedError, Sendable {
    case alreadyRecording
    case notRecording
    case insufficientDiskSpace(freeMB: Int64)
    case engineFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: "Recording is already active."
        case .notRecording: "No active recording session found."
        case .insufficientDiskSpace(let freeMB): "Insufficient disk space (\(freeMB) MB available). At least 100 MB required."
        case .engineFailed(let msg): "Audio engine failed: \(msg)"
        }
    }
}
