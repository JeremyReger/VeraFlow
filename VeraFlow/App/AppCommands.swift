import Observation
import SwiftUI

/// Requests from the Mac's menu bar and keyboard shortcuts (v1.1 plan item 15). The menu can't
/// reach the Library's state directly, so it bumps a counter here and the Library reacts in an
/// `onChange`. Present on every platform so the screens share one code path; only the Mac has
/// a menu bar that bumps it.
@Observable
@MainActor
final class AppCommands {
    private(set) var newRecordingRequests = 0
    private(set) var importRequests = 0
    private(set) var settingsRequests = 0
    private(set) var searchRequests = 0

    func requestNewRecording() { newRecordingRequests += 1 }
    func requestImport() { importRequests += 1 }
    func requestSettings() { settingsRequests += 1 }
    func requestSearch() { searchRequests += 1 }
}

#if os(macOS)
/// File › New Recording (⌘N), File › Import Audio… (⌘I), VeraFlow › Settings… (⌘,),
/// Edit › Find in Library (⌘F). Everything else comes from the standard menus.
struct AppMenuCommands: Commands {
    let commands: AppCommands

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recording") { commands.requestNewRecording() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Import Audio or Video…") { commands.requestImport() }
                .keyboardShortcut("i", modifiers: .command)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { commands.requestSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .textEditing) {
            Button("Find in Library") { commands.requestSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}
#endif
