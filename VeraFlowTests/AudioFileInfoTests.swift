import AVFAudio
import Foundation
import Testing
@testable import VeraFlow

/// Helpers that write small real audio files for tests.
enum TestAudioFiles {
    /// Writes `seconds` of silence as 16-bit PCM in a CAF container.
    static func writeSilentCAF(to url: URL, seconds: Double, sampleRate: Double = 8_000) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        file.close()
    }

    /// Writes `seconds` of a 440 Hz tone as AAC, in the container implied by the URL's extension
    /// (".aac" → ADTS, ".caf" → CAF), using the same settings as the live recorder.
    static func writeToneAAC(to url: URL, seconds: Double) throws {
        let sampleRate = 44_100.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let chunk: AVAudioFrameCount = 4_096
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk))
        let samples = try #require(buffer.floatChannelData?[0])
        var frame = 0
        let total = Int(seconds * sampleRate)
        while frame < total {
            let count = min(Int(chunk), total - frame)
            for i in 0..<count {
                samples[i] = 0.5 * sin(2 * .pi * 440 * Double(frame + i) / sampleRate).asFloat
            }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            frame += count
        }
        file.close()
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "VeraFlowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension Double {
    var asFloat: Float { Float(self) }
}

struct AudioFileInfoTests {
    @Test("A truncated ADTS AAC file is still readable (crash safety, SPEC §8.2)")
    func truncatedADTSIsReadable() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "audio.aac")
        try TestAudioFiles.writeToneAAC(to: url, seconds: 4)

        let full = try AudioFileInfo.duration(of: url)
        #expect(full > 3.5)

        // Simulate a force-quit: drop the tail of the file, mid-frame.
        let data = try Data(contentsOf: url)
        try data.prefix(data.count * 6 / 10).write(to: url)

        let truncated = try AudioFileInfo.duration(of: url)
        #expect(truncated > 1.0)
        #expect(truncated < full)
    }

    @Test("Duration comes from the file's frame count")
    func duration() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "audio.caf")
        try TestAudioFiles.writeSilentCAF(to: url, seconds: 2.5)

        let duration = try AudioFileInfo.duration(of: url)
        #expect(abs(duration - 2.5) < 0.001)
    }

    @Test("Missing or garbage files throw")
    func unreadable() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: (any Error).self) {
            try AudioFileInfo.duration(of: directory.appending(path: "missing.caf"))
        }

        let garbage = directory.appending(path: "garbage.caf")
        try Data("not audio".utf8).write(to: garbage)
        #expect(throws: (any Error).self) {
            try AudioFileInfo.duration(of: garbage)
        }
    }
}
