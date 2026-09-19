import AVFAudio
import Foundation
import MediaPlayer
import Observation

/// Minimal playback for one audio file: play, pause, seek, skip. The full Audio tab lands in M3+.
@Observable
@MainActor
final class AudioPlayerController {
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var errorMessage: String?
    /// 1×, 1.5×, 2× (design spec §4 Audio: the speed pill).
    private(set) var rate: Float = 1
    static let rates: [Float] = [1, 1.5, 2]
    /// e.g. "4.6 MB · 44100 Hz · 1 ch · aac" for the Status section (diagnostic).
    private(set) var fileDescription: String?
    /// Playback jumps over pauses (v1.1 plan item 9). Remembered in `UserDefaults`.
    private(set) var skipsSilence: Bool
    /// The pauses found in the loaded file; empty until the scan finishes or when there are none.
    private(set) var silentRanges: [SilentRange] = []
    /// True while the file is being scanned for pauses.
    private(set) var isScanningSilence = false
    /// Seconds "Skip silence" saves on this file.
    var silenceSavings: TimeInterval { SilenceDetector.totalDuration(silentRanges) }
    /// Peak levels are read once per file at this resolution.
    static let silenceBucketDuration: TimeInterval = 0.1

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var title = ""
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var silenceScan: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.skipsSilence = AppPreferences.skipsSilence(in: defaults)
    }

    /// The recording's audio isn't on this iPhone (an archive without it, v1.1 plan item 5):
    /// the player shows why instead of "file not found".
    func markUnavailable(_ message: String) {
        stop()
        errorMessage = message
    }

    func load(url: URL, title: String = "") {
        stop()
        self.title = title
        guard FileManager.default.fileExists(at: url) else {
            errorMessage = "Audio file not found."
            isLoaded = false
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.prepareToPlay()
            self.player = player
            // `AVAudioPlayer.duration` is an estimate for ADTS streams (no header carries the
            // length) and ran over a minute short on a 44-minute recording; count the frames instead.
            duration = (try? AudioFileInfo.duration(of: url)) ?? player.duration
            fileDescription = Self.describe(url: url, player: player)
            currentTime = 0
            errorMessage = nil
            isLoaded = true
            registerRemoteCommands()
            updateNowPlaying()
            scanSilence(url: url)
        } catch {
            errorMessage = "This recording can't be played: \(error.localizedDescription)"
            isLoaded = false
        }
    }

    private static func describe(url: URL, player: AVAudioPlayer) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int64) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let format = player.format
        let codec = (player.settings[AVFormatIDKey] as? UInt32).map { fourCharCode($0) } ?? "?"
        return "\(size) · \(Int(format.sampleRate)) Hz · \(format.channelCount) ch · \(codec)"
    }

    private static func fourCharCode(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func setSkipsSilence(_ enabled: Bool) {
        skipsSilence = enabled
        AppPreferences.setSkipsSilence(enabled, in: defaults)
        if enabled, isPlaying {
            skipSilenceIfNeeded()
        }
    }

    /// Reads the file's peak levels off the main actor and keeps the pauses; a new load cancels
    /// a scan still running.
    private func scanSilence(url: URL) {
        silenceScan?.cancel()
        silentRanges = []
        isScanningSilence = true
        let bucket = Self.silenceBucketDuration
        silenceScan = Task { @MainActor [weak self] in
            let ranges = await Task.detached(priority: .utility) { () -> [SilentRange] in
                guard let levels = try? WaveformPeaks.levels(url: url, bucketDuration: bucket) else { return [] }
                return SilenceDetector.ranges(levels: levels, bucketDuration: bucket)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.silentRanges = ranges
            self.isScanningSilence = false
        }
    }

    /// Jumps to the end of the pause the playhead is in. Called from the ticker while playing.
    private func skipSilenceIfNeeded() {
        guard skipsSilence, let player, let target = SilenceDetector.skipTarget(at: player.currentTime, in: silentRanges),
              target > player.currentTime, target < duration else { return }
        player.currentTime = target
        currentTime = target
    }

    /// Steps through `rates`; applies immediately if playing.
    func cycleRate() {
        let index = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(index + 1) % Self.rates.count]
        if isPlaying { player?.rate = rate }
        updateNowPlaying()
    }

    var rateLabel: String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
    }

    func play() {
        guard let player else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Playback couldn't start: \(error.localizedDescription)"
            return
        }
        #endif
        if player.currentTime >= duration {
            player.currentTime = 0
        }
        guard player.play() else {
            errorMessage = "Playback couldn't start."
            return
        }
        player.rate = rate
        isPlaying = true
        skipSilenceIfNeeded()
        startTicker()
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        currentTime = player?.currentTime ?? 0
        updateNowPlaying()
    }

    func stop() {
        silenceScan?.cancel()
        silenceScan = nil
        silentRanges = []
        isScanningSilence = false
        player?.stop()
        player = nil
        isPlaying = false
        stopTicker()
        currentTime = 0
        duration = 0
        isLoaded = false
        unregisterRemoteCommands()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), max(0, duration))
        player.currentTime = clamped
        currentTime = clamped
        updateNowPlaying()
    }

    // MARK: Lock Screen / Control Center (Now Playing)

    /// Title, length, position, and rate for the system's playback controls.
    private func updateNowPlaying() {
        guard isLoaded else { return }
        // With the app lock on, the Lock Screen and Control Center must not show the recording's
        // name (security review S-3).
        let shownTitle = AppPreferences.appLockEnabled() || title.isEmpty ? "Recording" : title
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: shownTitle,
            MPMediaItemPropertyArtist: "VeraFlow",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
        ]
    }

    private func registerRemoteCommands() {
        unregisterRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MPRemoteCommandEvent) -> Void) {
            command.isEnabled = true
            let target = command.addTarget { event in
                // The command center calls back on the main thread.
                MainActor.assumeIsolated { action(event) }
                return .success
            }
            commandTargets.append((command, target))
        }
        add(center.playCommand) { [weak self] _ in self?.play() }
        add(center.pauseCommand) { [weak self] _ in self?.pause() }
        add(center.togglePlayPauseCommand) { [weak self] _ in self?.togglePlayPause() }
        add(center.skipForwardCommand) { [weak self] _ in self?.skip(by: 15) }
        add(center.skipBackwardCommand) { [weak self] _ in self?.skip(by: -15) }
        add(center.changePlaybackPositionCommand) { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
            }
        }
    }

    private func unregisterRemoteCommands() {
        for (command, target) in commandTargets {
            command.removeTarget(target)
        }
        commandTargets = []
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    private func startTicker() {
        stopTicker()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard let player else { return }
        skipSilenceIfNeeded()
        currentTime = player.currentTime
        if !player.isPlaying, isPlaying {
            // Reached the end (or the system stopped us).
            isPlaying = false
            currentTime = player.currentTime >= duration - 0.05 ? duration : player.currentTime
            stopTicker()
            updateNowPlaying()
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }
}
