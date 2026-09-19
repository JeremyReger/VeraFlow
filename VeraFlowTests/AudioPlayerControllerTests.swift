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

    @Test func skipSilenceIsRememberedAndScansTheFile() async throws {
        let suite = "AudioPlayerControllerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = try TestAudioFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "audio.aac")
        try TestAudioFiles.writeToneAAC(to: url, seconds: 2)

        let controller = AudioPlayerController(defaults: defaults)
        #expect(!controller.skipsSilence)
        controller.setSkipsSilence(true)
        #expect(AppPreferences.skipsSilence(in: defaults))
        #expect(AudioPlayerController(defaults: defaults).skipsSilence)

        controller.load(url: url)
        // A steady tone has no pauses; the scan finishes with nothing to skip.
        for _ in 0..<50 where controller.isScanningSilence {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!controller.isScanningSilence)
        #expect(controller.silentRanges.isEmpty)
        #expect(controller.silenceSavings == 0)
        controller.stop()
    }
}
