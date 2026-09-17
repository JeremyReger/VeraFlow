import Testing
import Foundation

@Suite("Network Policy & Privacy Enforcement Tests (§14.1)")
struct NetworkPolicyTests {
    @Test("Verify zero unauthorized URLSession usage in app source files")
    func testZeroUnauthorizedNetworkCalls() throws {
        // Search the VeraFlow source directory for URLSession usages
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let appSourceDir = repoRoot.appendingPathComponent("VeraFlow")
        
        guard FileManager.default.fileExists(atPath: appSourceDir.path) else {
            // If running in isolated bundle, skip filesystem scan
            return
        }
        
        let enumerator = FileManager.default.enumerator(at: appSourceDir, includingPropertiesForKeys: [.isRegularFileKey])
        var violations: [String] = []
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            
            // Allow-listed files for external model assets (§14.1)
            let fileName = fileURL.lastPathComponent
            if fileName.contains("ModelDownload") || fileName.contains("AssetDownloader") {
                continue
            }
            
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            if content.contains("URLSession") {
                violations.append(fileURL.lastPathComponent)
            }
        }
        
        #expect(violations.isEmpty, "Found unauthorized URLSession occurrences in: \(violations.joined(separator: ", "))")
    }
}
