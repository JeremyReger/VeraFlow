import AVFAudio
import Foundation

/// Reads facts about an audio file without loading it into memory.
enum AudioFileInfo {
    /// Duration in seconds, taken from the file's frame count. Throws if the file can't be opened.
    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(file.length) / sampleRate
    }
}
