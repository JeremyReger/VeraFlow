import Observation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Builds a `.veraflowarchive` package in `tmp/Exports/` and hands it to the system picker so
/// the user chooses where it goes (iCloud Drive, a USB drive, any file provider). No network
/// call is made by VeraFlow (v1.1 plan item 5).
@Observable
@MainActor
final class ArchiveExportController {
    /// What the picker shows: the package itself, or its zip when iOS doesn't know the package type.
    var exportURL: URL?
    /// The package folder in `tmp/Exports/`, removed with the zip (if any) when the picker closes.
    private var packageURL: URL?
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
            packageURL = destination
            // The export picker refuses plain directories; a package it knows is fine, and a
            // package it doesn't know goes as a zip (Files unpacks it with a tap).
            exportURL = try await Task.detached(priority: .userInitiated) {
                try LibraryArchive.exportItem(for: destination)
            }.value
        } catch {
            errorMessage = "Couldn't build the archive: \(error.localizedDescription)"
        }
    }

    /// The picker closed: the temporary package (and zip) are removed whether or not it was saved.
    func finish() {
        for url in [exportURL, packageURL].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
        packageURL = nil
    }
}

#if os(iOS)
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
#elseif os(macOS)
/// The Mac's "choose a folder" panel; the package is copied into the chosen folder (v1.1 plan
/// item 15). The panel grants sandbox access to that folder for the copy.
@MainActor
enum MacFolderPicker {
    static func chooseFolder(prompt: String, message: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        let response = await panel.begin()
        return response == .OK ? panel.url : nil
    }

    static func copy(_ item: URL, into folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let destination = folder.appending(path: item.lastPathComponent)
        if FileManager.default.fileExists(at: destination) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: item, to: destination)
    }
}
#endif

/// Presents the picker and the error alert for an `ArchiveExportController`.
struct ArchiveExportPresentation: ViewModifier {
    @Bindable var controller: ArchiveExportController

    func body(content: Content) -> some View {
        picker(content)
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

    #if os(iOS)
    private func picker(_ content: Content) -> some View {
        content
            .sheet(item: Binding(
                get: { controller.exportURL.map { ShareItem(url: $0) } },
                set: { if $0 == nil { controller.finish() } }
            )) { item in
                DocumentExportPicker(url: item.url) { controller.finish() }
                    .ignoresSafeArea()
            }
    }
    #else
    private func picker(_ content: Content) -> some View {
        content
            .onChange(of: controller.exportURL) { _, url in
                guard let url else { return }
                Task { @MainActor in
                    if let folder = await MacFolderPicker.chooseFolder(prompt: "Export", message: "Choose where to save the VeraFlow archive.") {
                        do {
                            try MacFolderPicker.copy(url, into: folder)
                        } catch {
                            controller.errorMessage = "Couldn't save the archive: \(error.localizedDescription)"
                        }
                    }
                    controller.finish()
                }
            }
    }
    #endif
}
