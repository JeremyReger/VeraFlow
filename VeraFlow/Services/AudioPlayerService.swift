import Foundation
import AVFoundation
import Observation

/// Audio playback service managing synchronized transcript highlighting and playback (§4.4, §16 M3)
@Observable
@MainActor
public final class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    public var isPlaying: Bool = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var playbackRate: Float = 1.0
    public var errorMessage: String? = nil
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    public override init() {
        super.init()
    }
    
    public func loadAudio(from url: URL) {
        stop()
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Audio file not found."
            return
        }
        
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            #endif
            
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.enableRate = true
            newPlayer.rate = playbackRate
            newPlayer.prepareToPlay()
            
            self.player = newPlayer
            self.duration = newPlayer.duration
            self.currentTime = 0
            self.isPlaying = false
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Could not load audio: \(error.localizedDescription)"
        }
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func play() {
        guard let player else { return }
        player.rate = playbackRate
        player.play()
        isPlaying = true
        startTimer()
    }
    
    public func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }
    
    public func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
    }
    
    public func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        player.currentTime = clamped
        currentTime = clamped
        if !isPlaying {
            player.prepareToPlay()
        }
    }
    
    public func cyclePlaybackRate() {
        switch playbackRate {
        case 1.0: playbackRate = 1.5
        case 1.5: playbackRate = 2.0
        default: playbackRate = 1.0
        }
        player?.rate = playbackRate
    }
    
    // MARK: - Timer & Delegates
    
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }
}
