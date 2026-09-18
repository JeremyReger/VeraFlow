import Foundation
import Testing
@testable import VeraFlow

/// The PDF and text paths run in the Simulator; Reminders and the audio export need a device.
@MainActor
struct LiveExportServiceTests {
    @Test("The PDF is a real multi-page document with page footers")
    func pdf() async throws {
        let service = LiveExportService()
        var document = ExportDocument.make(from: PreviewData.sampleRecording(), includeTranscript: true)
        // Pad the transcript so it must paginate.
        document.segments = (0..<120).map { index in
            ExportSegment(start: Double(index) * 20, speakerKey: index % 2 == 0 ? "S1" : "S2", text: String(repeating: "We need the permit before we pour the footer. ", count: 4))
        }
        let data = try await service.pdf(for: document)
        let header = String(decoding: data.prefix(5), as: UTF8.self)
        #expect(header == "%PDF-")
        let body = String(decoding: data, as: UTF8.self)
        let pages = body.components(separatedBy: "/Type /Page").count - 1
        #expect(pages > 2, "expected several pages, found \(pages)")
    }

    @Test("Markdown and plain text come from the renderer; file names follow the spec pattern")
    func textPaths() async {
        let service = LiveExportService()
        let document = ExportDocument.make(from: PreviewData.sampleRecording(), includeTranscript: false)
        #expect(await service.markdown(for: document) == ExportRenderer.markdown(for: document))
        #expect(await service.plainText(for: document) == ExportRenderer.plainText(for: document))
        let name = await service.fileName(for: document, fileExtension: "md")
        #expect(name.hasSuffix(" Kitchen remodel walk-through.md"))
        #expect(name.count == "YYYY-MM-DD".count + " Kitchen remodel walk-through.md".count)
    }
}
