import AppIntents
import Foundation

/// What a Live Activity button asks the app to do (SPEC §4.2 step 3 stretch: Lock Screen controls).
enum RecordingControlAction: String, Sendable {
    case pause
    case resume
    case bookmark
}

/// Hands widget button presses to the running recorder. `LiveActivityIntent`s perform inside the
/// app's own process, so the recorder view model registers a handler while it is recording.
@MainActor
final class RecordingControlHub {
    static let shared = RecordingControlHub()

    var handler: ((RecordingControlAction) async -> Void)?

    func perform(_ action: RecordingControlAction) async {
        await handler?(action)
    }
}

#if os(iOS)
struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Recording"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RecordingControlHub.shared.perform(.pause)
        return .result()
    }
}

struct ResumeRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Recording"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RecordingControlHub.shared.perform(.resume)
        return .result()
    }
}

struct AddBookmarkIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add Bookmark"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await RecordingControlHub.shared.perform(.bookmark)
        return .result()
    }
}
#endif
