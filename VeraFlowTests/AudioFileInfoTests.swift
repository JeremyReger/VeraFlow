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

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "VeraFlowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

struct AudioFileInfoTests {
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
