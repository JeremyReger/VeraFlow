import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import VeraFlow

/// The platform seams the Mac target adds (v1.1 plan item 15). Everything here is pure; the
/// Core Audio device list and the panels need a Mac session.
@MainActor
struct MacPlatformTests {
    @Test("The device noun follows the platform and the phrases read naturally")
    func deviceNoun() {
        #if os(macOS)
        #expect(Platform.isMac)
        #expect(Platform.deviceNoun == "Mac")
        #expect(Platform.thisDevice == "this Mac")
        #expect(Platform.thisDeviceCapitalized == "This Mac")
        #expect(Platform.builtInMicrophoneName == "Mac Microphone")
        #else
        #expect(!Platform.isMac)
        #expect(Platform.deviceNoun == "iPhone")
        #expect(Platform.thisDevice == "this iPhone")
        #expect(Platform.thisDeviceCapitalized == "This iPhone")
        #expect(Platform.builtInMicrophoneName == "iPhone Microphone")
        #endif
        #expect(Platform.yourDevice == "your \(Platform.deviceNoun)")
        #expect(Platform.microphoneSettingsURL != nil)
        #expect(Platform.osName == (Platform.isMac ? "macOS" : "iOS"))
        // The Mac's permission panes live in System Settings; the iPhone's in Settings.
        #expect(Platform.settingsAppName == (Platform.isMac ? "System Settings" : "Settings"))
    }

    @Test("Copy that names the device uses the platform's noun, never a hard-coded iPhone on the Mac")
    func copyFollowsPlatform() {
        let message = OnboardingView.transcriptionMessage(.allAvailable)
        #expect(message.contains(Platform.thisDevice))
        let summary = OnboardingView.summaryMessage(.deviceNotEligible)
        #expect(summary.contains(Platform.deviceNoun))
        #if os(macOS)
        #expect(!message.contains("iPhone"))
        #expect(!summary.contains("iPhone"))
        #endif
    }

    @Test("Each export kind maps to the type the Mac's save panel is told")
    func exportContentTypes() {
        #expect(ExportKind.pdf.contentType == .pdf)
        #expect(ExportKind.plainText.contentType == .plainText)
        #expect(ExportKind.audio.contentType == .mpeg4Audio)
        // Markdown is a known type on current systems; the fallback is plain text.
        #expect(ExportKind.markdown.contentType == (UTType("net.daringfireball.markdown") ?? .plainText))
        let item = ShareItem(url: URL(filePath: "/tmp/x.pdf"), kind: .pdf)
        #expect(item.contentType == .pdf)
        // A package (the library archive) has no kind and falls back to the extension, else data.
        let archive = ShareItem(url: URL(filePath: "/tmp/library.veraflowarchive"))
        #expect(archive.kind == nil)
        #expect(archive.contentType == (UTType(filenameExtension: "veraflowarchive") ?? .data))
    }

    @Test("Menu-bar requests count up so a screen can react in onChange")
    func commands() {
        let commands = AppCommands()
        #expect(commands.newRecordingRequests == 0)
        commands.requestNewRecording()
        commands.requestNewRecording()
        commands.requestImport()
        commands.requestSettings()
        commands.requestSearch()
        #expect(commands.newRecordingRequests == 2)
        #expect(commands.importRequests == 1)
        #expect(commands.settingsRequests == 1)
        #expect(commands.searchRequests == 1)
    }

    @Test("A no-op activity service accepts every call")
    func noActivity() async {
        let service = NoRecordingActivityService()
        let state = RecordingActivityAttributes.ContentState.make(elapsed: 3, isPaused: false, bookmarkCount: 0, now: .now)
        await service.start(recordingID: UUID(), title: "Standup", state: state)
        await service.update(state)
        await service.end()
    }

    @Test("Input changes need an engine restart only where there is no audio session")
    func inputRestartPolicy() {
        #if os(macOS)
        #expect(RecorderPlatform.inputChangeNeedsRestart)
        #else
        #expect(!RecorderPlatform.inputChangeNeedsRestart)
        #endif
    }

    @Test("File protection attributes exist on iOS and are empty on the Mac")
    func protectionAttributes() {
        let attributes = DataProtection.newFileAttributes
        #if os(macOS)
        #expect(attributes.isEmpty)
        #else
        #expect(attributes[.protectionKey] as? FileProtectionType == .completeUntilFirstUserAuthentication)
        #endif
    }

    @Test("Background processing is reported unsupported on the Mac and in the Simulator")
    func backgroundSupport() {
        if #available(iOS 26, *) {
            #if os(macOS) || targetEnvironment(simulator)
            #expect(!LiveCapabilityService.backgroundProcessingSupported)
            #else
            #expect(LiveCapabilityService.backgroundProcessingSupported)
            #endif
        }
    }

    @Test("The PDF composer draws the same document on both platforms")
    func pdfOnBothPlatforms() {
        let document = ExportDocument.make(from: PreviewData.sampleRecording(), includeTranscript: true)
        let data = PDFComposer.render(document)
        #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
        let body = String(decoding: data, as: UTF8.self)
        #expect(body.contains("/Type /Page"))
        #expect(body.contains("VeraFlow"))   // the creator metadata
    }
}
