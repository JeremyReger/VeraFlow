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
    /// "Transcribe again in…" (v1.1 plan item 8).
    var retranscribeTarget: Recording?
    /// "Export recording…" (v1.1 plan item 5).
    let archiveExport = ArchiveExportController()
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

    /// Takes the recording explicitly: SwiftUI dismisses the alert (which clears `renameTarget`)
    /// before it runs the Save action, so the target can't be read back here.
    func commitRename(_ recording: Recording) {
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

    func beginRetranscribe(_ recording: Recording) {
        retranscribeTarget = recording
    }

    func exportPackage(_ recording: Recording) async {
        await archiveExport.exportRecording(recording, using: actions)
    }

    func confirmRetranscribe(_ recording: Recording, in locale: Locale) async {
        retranscribeTarget = nil
        do {
            try await actions.retranscribe(recording, in: locale)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Same as `commitRename`: the dialog is already dismissed when this runs. Delete moves the
    /// recording to Recently Deleted (v1.1 plan item 10); Settings → Storage removes it for good.
    func confirmDelete(_ recording: Recording) async {
        deleteTarget = nil
        do {
            try await actions.trash(recording)
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
        if recording.stage != .ready || recording.failedStage != nil {
            Button("Process next", systemImage: "arrow.up.to.line") {
                Task { await controller.actions.services.pipeline.prioritize(recordingID: recording.id) }
            }
        }
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
        Button("Transcribe again in…", systemImage: "globe") {
            controller.beginRetranscribe(recording)
        }
        .disabled(recording.stage == .recording || recording.stage.isProcessing || !recording.audioAvailable)
        Button("Export recording…", systemImage: "shippingbox") {
            Task { await controller.exportPackage(recording) }
        }
        .disabled(recording.stage == .recording)
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
            ), presenting: controller.renameTarget) { recording in
                TextField("Title", text: $controller.renameDraft)
                    .accessibilityIdentifier("rename.field")
                Button("Save") { controller.commitRename(recording) }
                Button("Cancel", role: .cancel) { controller.cancelRename() }
            }
            .sheet(item: $controller.tagTarget) { recording in
                TagEditorView(tags: recording.tags, suggestions: allTags) { tags in
                    controller.saveTags(recording, tags)
                }
            }
            .sheet(item: $controller.retranscribeTarget) { recording in
                RetranscribeSheet(recording: recording) { locale in
                    Task { await controller.confirmRetranscribe(recording, in: locale) }
                }
            }
            .modifier(ArchiveExportPresentation(controller: controller.archiveExport))
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { controller.deleteTarget != nil },
                set: { if !$0 { controller.deleteTarget = nil } }
            ), titleVisibility: .visible, presenting: controller.deleteTarget) { recording in
                Button("Delete", role: .destructive) {
                    Task { await controller.confirmDelete(recording) }
                }
                Button("Cancel", role: .cancel) { controller.deleteTarget = nil }
            } message: { _ in
                Text("It moves to Recently Deleted for \(Int(TrashPolicy.retention / 86_400)) days, where you can restore it from Settings.")
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
