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
    /// e.g. "4.6 MB · 44100 Hz · 1 ch · aac" for the Status section (diagnostic).
    private(set) var fileDescription: String?

    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var title = ""
    private var commandTargets: [(MPRemoteCommand, Any)] = []

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

    func play() {
        guard let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            errorMessage = "Playback couldn't start: \(error.localizedDescription)"
            return
        }
        if player.currentTime >= duration {
            player.currentTime = 0
        }
        guard player.play() else {
            errorMessage = "Playback couldn't start."
            return
        }
        isPlaying = true
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title.isEmpty ? "Recording" : title,
            MPMediaItemPropertyArtist: "VeraFlow",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
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
        currentTime = player.currentTime
        if !player.isPlaying, isPlaying {
            // Reached the end (or the system stopped us).
            isPlaying = false
            currentTime = player.currentTime >= duration - 0.05 ? duration : player.currentTime
            stopTicker()
            updateNowPlaying()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
