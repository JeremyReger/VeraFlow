import Observation
import SwiftUI
import UIKit

/// Builds a `.veraflowarchive` package in `tmp/Exports/` and hands it to the system picker so
/// the user chooses where it goes (iCloud Drive, a USB drive, any file provider). No network
/// call is made by VeraFlow (v1.1 plan item 5).
@Observable
@MainActor
final class ArchiveExportController {
    var exportURL: URL?
    var errorMessage: String?
    private(set) var isWorking = false
    private(set) var progress: Double = 0

    /// The whole library (Recently Deleted excluded).
    func exportLibrary(_ recordings: [Recording], using actions: LibraryActions) async {
        let name = LibraryArchive.packageName(for: "VeraFlow library", createdAt: .now)
        await run(recordings, name: name, using: actions)
    }

    /// One recording, for moving it to another iPhone.
    func exportRecording(_ recording: Recording, using actions: LibraryActions) async {
        let name = LibraryArchive.packageName(for: LibraryCardModel(recording: recording).title, createdAt: recording.createdAt)
        await run([recording], name: name, using: actions)
    }

    private func run(_ recordings: [Recording], name: String, using actions: LibraryActions) async {
        guard !isWorking else { return }
        isWorking = true
        progress = 0
        defer { isWorking = false }
        let destination = ExportController.exportsDirectory().appending(path: name, directoryHint: .isDirectory)
        do {
            try await actions.exportArchive(recordings, to: destination) { fraction in
                Task { @MainActor [weak self] in self?.progress = fraction }
            }
            exportURL = destination
        } catch {
            errorMessage = "Couldn't build the archive: \(error.localizedDescription)"
        }
    }

    /// The picker closed: the temporary package is removed whether or not it was saved.
    func finish() {
        if let exportURL {
            try? FileManager.default.removeItem(at: exportURL)
        }
        exportURL = nil
    }
}

/// `UIDocumentPickerViewController` in export mode: the user picks a folder and the system
/// copies the package there.
struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Task { @MainActor in self.onDone() }
        }

        nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            Task { @MainActor in self.onDone() }
        }
    }
}

/// Presents the picker and the error alert for an `ArchiveExportController`.
struct ArchiveExportPresentation: ViewModifier {
    @Bindable var controller: ArchiveExportController

    func body(content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { controller.exportURL.map { ShareItem(url: $0) } },
                set: { if $0 == nil { controller.finish() } }
            )) { item in
                DocumentExportPicker(url: item.url) { controller.finish() }
                    .ignoresSafeArea()
            }
            .alert("Export problem", isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )) {
                Button("OK") { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
            .overlay {
                if controller.isWorking {
                    ProgressView(value: controller.progress) {
                        Text("Building the archive…")
                    }
                    .progressViewStyle(.linear)
                    .padding()
                    .frame(maxWidth: 260)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: VFRadius.block))
                    .accessibilityLabel("Building the archive")
                }
            }
    }
}
