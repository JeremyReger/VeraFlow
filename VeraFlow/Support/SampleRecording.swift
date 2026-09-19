import Foundation

/// The bundled sample recording (SPEC §0 demo mode, v1.1 plan item 7): a VeraFlow archive
/// copied into the app bundle, imported like any other package with `source = .sample` and the
/// "Sample" tag. Hidden entirely while the bundle folder holds no archive.
enum SampleRecording {
    static let folderName = "SampleRecording"
    static let tag = "Sample"

    /// The bundled package, if the folder holds one.
    static var bundledPackageURL: URL? {
        guard let url = Bundle.main.url(forResource: folderName, withExtension: nil) else { return nil }
        return isPackage(url) ? url : nil
    }

    static var isAvailable: Bool { bundledPackageURL != nil }

    static func isPackage(_ url: URL) -> Bool {
        FileManager.default.fileExists(at: url.appending(path: LibraryArchive.manifestName))
    }

    /// Imports the package. Already in the Library (or in Recently Deleted) → nothing is added.
    /// The bundled summary comes along, so no free summary is spent.
    @MainActor
    @discardableResult
    static func install(from packageURL: URL, using actions: LibraryActions) async throws -> ArchiveImportOutcome {
        try await actions.importArchive(from: packageURL, source: .sample, extraTags: [tag])
    }
}
