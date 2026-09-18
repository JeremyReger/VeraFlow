import Foundation
import Testing
@testable import VeraFlow

struct PhotosVideoImportTests {
    @Test("Photos copies keep a lowercased extension, default to mov, and are unique")
    func destinations() {
        let id = UUID()
        let mov = PhotosVideoImport.temporaryDestination(for: URL(filePath: "/tmp/IMG_0001.MOV"), id: id)
        #expect(mov.lastPathComponent == "\(id.uuidString).mov")
        #expect(mov.deletingLastPathComponent() == PhotosVideoImport.folder)

        let mp4 = PhotosVideoImport.temporaryDestination(for: URL(filePath: "/tmp/clip.mp4"), id: id)
        #expect(mp4.pathExtension == "mp4")

        let bare = PhotosVideoImport.temporaryDestination(for: URL(filePath: "/tmp/noext"), id: id)
        #expect(bare.pathExtension == "mov")

        let other = PhotosVideoImport.temporaryDestination(for: URL(filePath: "/tmp/IMG_0001.MOV"))
        #expect(other != mov)
    }
}
