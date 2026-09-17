import AVFAudio
import Foundation
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

    func load(url: URL) {
        stop()
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
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
        currentTime = player?.currentTime ?? 0
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        stopTicker()
        currentTime = 0
        duration = 0
        isLoaded = false
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), max(0, duration))
        player.currentTime = clamped
        currentTime = clamped
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
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
