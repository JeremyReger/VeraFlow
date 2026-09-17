import Foundation
import Observation
import SwiftUI

/// Presentation state for rename / tags / delete on a recording, shared by the Library rows and
/// the detail screen so both get the same alerts and sheets.
@Observable
@MainActor
final class RecordingActionsController {
    var renameTarget: Recording?
    var renameDraft = ""
    var tagTarget: Recording?
    var deleteTarget: Recording?
    var errorMessage: String?
    /// Called after a recording is deleted, e.g. so the detail screen can pop.
    var onDeleted: ((Recording) -> Void)?

    let actions: LibraryActions

    init(actions: LibraryActions) {
        self.actions = actions
    }

    func beginRename(_ recording: Recording) {
        renameDraft = recording.title
        renameTarget = recording
    }

    func commitRename() {
        guard let recording = renameTarget else { return }
        renameTarget = nil
        do {
            try actions.rename(recording, to: renameDraft)
        } catch LibraryActionError.emptyTitle {
            errorMessage = "A recording needs a title."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelRename() {
        renameTarget = nil
    }

    func toggleFavorite(_ recording: Recording) {
        do {
            try actions.toggleFavorite(recording)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginTags(_ recording: Recording) {
        tagTarget = recording
    }

    func saveTags(_ recording: Recording, _ tags: [String]) {
        do {
            try actions.setTags(recording, to: tags)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestDelete(_ recording: Recording) {
        deleteTarget = recording
    }

    func confirmDelete() async {
        guard let recording = deleteTarget else { return }
        deleteTarget = nil
        do {
            try await actions.delete(recording)
            onDeleted?(recording)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The Rename / Favorite / Tags / Delete buttons, for a context menu or a toolbar menu.
struct RecordingMenuItems: View {
    let recording: Recording
    let controller: RecordingActionsController

    var body: some View {
        Button("Rename", systemImage: "pencil") {
            controller.beginRename(recording)
        }
        Button(recording.isFavorite ? "Remove Favorite" : "Favorite",
               systemImage: recording.isFavorite ? "star.slash" : "star") {
            controller.toggleFavorite(recording)
        }
        Button("Tags", systemImage: "tag") {
            controller.beginTags(recording)
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            controller.requestDelete(recording)
        }
    }
}

/// Attaches the rename alert, tag editor sheet, delete confirmation, and error alert.
struct RecordingActionsModifier: ViewModifier {
    @Bindable var controller: RecordingActionsController
    let allTags: [String]

    func body(content: Content) -> some View {
        content
            .alert("Rename recording", isPresented: Binding(
                get: { controller.renameTarget != nil },
                set: { if !$0 { controller.cancelRename() } }
            )) {
                TextField("Title", text: $controller.renameDraft)
                    .accessibilityIdentifier("rename.field")
                Button("Save") { controller.commitRename() }
                Button("Cancel", role: .cancel) { controller.cancelRename() }
            }
            .sheet(item: $controller.tagTarget) { recording in
                TagEditorView(tags: recording.tags, suggestions: allTags) { tags in
                    controller.saveTags(recording, tags)
                }
            }
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { controller.deleteTarget != nil },
                set: { if !$0 { controller.deleteTarget = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await controller.confirmDelete() }
                }
                Button("Cancel", role: .cancel) { controller.deleteTarget = nil }
            } message: {
                Text("This removes the audio and everything made from it.")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )) {
                Button("OK") { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
    }
}
