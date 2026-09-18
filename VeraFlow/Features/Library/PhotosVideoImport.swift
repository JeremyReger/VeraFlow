import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video chosen in the Photos picker. The picker hands over a temporary file that goes away
/// when the transfer ends, so it is copied into `tmp/PhotoImports/` first; the importer then
/// extracts the audio track from that copy like any other mp4/mov. `.movie` covers mp4, mov, m4v.
struct PickedVideo: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = PhotosVideoImport.temporaryDestination(for: received.file)
            let manager = FileManager.default
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.removeItem(at: destination)
            try manager.copyItem(at: received.file, to: destination)
            return PickedVideo(url: destination)
        }
    }
}

enum PhotosVideoImport {
    static let folder = FileManager.default.temporaryDirectory
        .appending(path: "PhotoImports", directoryHint: .isDirectory)

    /// A unique path in `folder` that keeps the picker file's extension (lowercased) so the
    /// importer recognises the container; a video without one is treated as `.mov`.
    static func temporaryDestination(for original: URL, id: UUID = UUID()) -> URL {
        let ext = original.pathExtension.lowercased()
        return folder.appending(path: "\(id.uuidString).\(ext.isEmpty ? "mov" : ext)")
    }
}
