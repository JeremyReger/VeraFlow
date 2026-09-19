import AVFAudio
import Foundation

/// Reads facts about an audio file without loading it into memory.
enum AudioFileInfo {
    /// True when the file is missing or holds no bytes — capture wrote nothing. Worth asking
    /// before opening it: an empty file fails with a Core Audio error number that says nothing.
    static func isEmpty(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attributes[.size] as? Int else { return true }
        return size == 0
    }

    /// Duration in seconds, taken from the file's frame count. Throws if the file can't be opened.
    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.fileFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(file.length) / sampleRate
    }
}
