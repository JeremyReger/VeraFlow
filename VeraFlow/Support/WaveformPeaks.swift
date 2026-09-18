import AVFAudio
import Foundation

/// Bars for the Audio tab's waveform scrubber: one 0...1 peak per bar, read straight from the
/// audio file without holding it in memory (design spec §4 Audio).
enum WaveformPeaks {
    /// Splits `levels` into `count` buckets, keeps the loudest sample of each, and scales the
    /// result so the loudest bar is 1. Fewer levels than buckets pads with silence.
    static func buckets(_ levels: [Float], count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0, count: count) }
        let perBucket = max(1, Int((Double(levels.count) / Double(count)).rounded(.up)))
        var peaks: [Float] = []
        peaks.reserveCapacity(count)
        var index = 0
        while peaks.count < count {
            let end = min(index + perBucket, levels.count)
            var peak: Float = 0
            if index < end {
                for i in index..<end {
                    peak = max(peak, abs(levels[i]))
                }
            }
            peaks.append(peak)
            index = end
        }
        return normalized(peaks)
    }

    /// Reads the whole file in chunks and returns `barCount` peaks. Slow for long recordings
    /// (it decodes every frame), so call it off the main actor and check for cancellation.
    static func compute(url: URL, barCount: Int) throws -> [CGFloat] {
        guard barCount > 0 else { return [] }
        let file = try AVAudioFile(forReading: url)
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return Array(repeating: 0, count: barCount) }
        let framesPerBar = max(1, Int((Double(totalFrames) / Double(barCount)).rounded(.up)))
        let chunk: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else {
            return Array(repeating: 0, count: barCount)
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(barCount)
        var barPeak: Float = 0
        var framesInBar = 0
        while file.framePosition < file.length, peaks.count < barCount {
            if Task.isCancelled { throw CancellationError() }
            try file.read(into: buffer, frameCount: chunk)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }
            let channelCount = Int(buffer.format.channelCount)
            for frame in 0..<frames {
                var level: Float = 0
                for channel in 0..<channelCount {
                    level = max(level, abs(channels[channel][frame]))
                }
                barPeak = max(barPeak, level)
                framesInBar += 1
                if framesInBar == framesPerBar {
                    peaks.append(barPeak)
                    barPeak = 0
                    framesInBar = 0
                    if peaks.count == barCount { break }
                }
            }
        }
        if framesInBar > 0, peaks.count < barCount {
            peaks.append(barPeak)
        }
        while peaks.count < barCount {
            peaks.append(0)
        }
        return normalized(peaks)
    }

    private static func normalized(_ peaks: [Float]) -> [CGFloat] {
        let loudest = peaks.max() ?? 0
        guard loudest > 0 else { return peaks.map { _ in 0 } }
        return peaks.map { CGFloat($0 / loudest) }
    }
}
