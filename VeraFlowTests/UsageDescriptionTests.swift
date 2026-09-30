import Foundation
import Testing

/// SPEC §14.5: a permission the code asks for and the Info.plist doesn't explain is not a warning,
/// it is a crash the first time the user taps Record — and an App Review rejection. A usage string
/// the code never earns is the opposite problem: a reviewer asking why the app wants something it
/// doesn't use. Both directions are checked, for both app targets, because they compile the same
/// sources and so imply the same permissions.
struct UsageDescriptionTests {
    /// Source markers that mean a permission is requested → the key that must explain it.
    /// `AVCaptureDevice` is the Mac's microphone permission (`RecorderPlatform`), `LAContext` the
    /// app lock, `EKEventStore` the Reminders export.
    private static let required: [(markers: [String], key: String)] = [
        (["AVAudioApplication.requestRecordPermission", "AVCaptureDevice"], "NSMicrophoneUsageDescription"),
        (["LAContext"], "NSFaceIDUsageDescription"),
        (["EKEventStore"], "NSRemindersFullAccessUsageDescription"),
    ]

    private static func appSourceText() throws -> String {
        try SourceTree.appSourceFiles()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    @Test("Every permission the sources request is explained, in both app targets", arguments: ProjectSpecReader.appTargets)
    func everyRequestedPermissionIsExplained(target: String) throws {
        let sources = try Self.appSourceText()
        let declared = try ProjectSpecReader.usageDescriptionKeys(forTarget: target)
        for entry in Self.required where entry.markers.contains(where: { sources.contains($0) }) {
            #expect(
                declared.contains(entry.key),
                "\(target) requests this permission but declares no \(entry.key); the system kills the app on the first request"
            )
        }
    }

    @Test("No target asks for a permission the code never uses", arguments: ProjectSpecReader.appTargets)
    func noUnearnedUsageDescriptions(target: String) throws {
        let sources = try Self.appSourceText()
        let known = Dictionary(uniqueKeysWithValues: Self.required.map { ($0.key, $0.markers) })
        for key in try ProjectSpecReader.usageDescriptionKeys(forTarget: target) {
            guard let markers = known[key] else {
                Issue.record("\(target) declares \(key), which this test doesn't know about. Add it to `required` with the API that earns it.")
                continue
            }
            #expect(
                markers.contains(where: { sources.contains($0) }),
                "\(target) declares \(key) but no source calls the API behind it. An unearned permission string invites a review question."
            )
        }
    }
}
