import Foundation
import Testing
@testable import VeraFlow

@MainActor
struct AudioPlayerControllerTests {
    /// ADTS has no length header, so `AVAudioPlayer.duration` guesses from the bit rate. The
    /// controller must report the frame-counted duration instead (it ran short on a long recording).
    @Test func durationComesFromFrameCountForADTS() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "audio.aac")
        try TestAudioFiles.writeToneAAC(to: url, seconds: 3)

        let controller = AudioPlayerController()
        controller.load(url: url)

        #expect(controller.isLoaded)
        #expect(controller.errorMessage == nil)
        let expected = try AudioFileInfo.duration(of: url)
        #expect(abs(controller.duration - expected) < 0.001)
        #expect(abs(controller.duration - 3) < 0.25)
    }

    @Test func seekClampsToFrameCountedDuration() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "audio.aac")
        try TestAudioFiles.writeToneAAC(to: url, seconds: 2)

        let controller = AudioPlayerController()
        controller.load(url: url)
        controller.seek(to: 60)
        #expect(abs(controller.currentTime - controller.duration) < 0.001)

        controller.seek(to: -5)
        #expect(controller.currentTime == 0)
    }

    @Test func missingFileReportsError() throws {
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = AudioPlayerController()
        controller.load(url: directory.appending(path: "nope.aac"))
        #expect(!controller.isLoaded)
        #expect(controller.errorMessage == "Audio file not found.")
    }
}
