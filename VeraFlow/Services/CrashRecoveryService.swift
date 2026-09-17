import Foundation
import SwiftData
import AVFoundation

/// Scans for and restores incomplete or interrupted recordings on application launch (§8.2)
public final class CrashRecoveryService: Sendable {
    public init() {}
    
    /// Scans the provided ModelContext for recordings left in the `.recording` stage and finalizes them.
    /// Returns the list of recovered recording titles.
    @MainActor
    public func scanAndRecover(in context: ModelContext, recordingsBaseURL: URL) -> [String] {
        var recoveredTitles: [String] = []
        
        let descriptor = FetchDescriptor<Recording>()
        guard let allRecordings = try? context.fetch(descriptor) else {
            return []
        }
        
        for recording in allRecordings where recording.stage == .recording {
            let audioURL = recordingsBaseURL.appendingPathComponent(recording.audioFileName)
            
            if FileManager.default.fileExists(atPath: audioURL.path) {
                do {
                    let audioFile = try AVAudioFile(forReading: audioURL)
                    let sampleRate = audioFile.processingFormat.sampleRate
                    let duration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
                    
                    recording.duration = duration
                    recording.stage = .recorded
                    recording.failureMessage = "Recovered an interrupted recording."
                    
                    // Add a bookmark noting where crash recovery occurred
                    let bookmark = Bookmark(time: duration, note: "Interrupted / Crash Recovered")
                    recording.bookmarks.append(bookmark)
                    
                    recoveredTitles.append(recording.title)
                } catch {
                    recording.stage = .failed
                    recording.failureMessage = "Could not finalize interrupted recording: \(error.localizedDescription)"
                }
            } else {
                recording.stage = .failed
                recording.failureMessage = "Audio file missing after interruption."
            }
        }
        
        if !recoveredTitles.isEmpty {
            try? context.save()
        }
        
        return recoveredTitles
    }
}
