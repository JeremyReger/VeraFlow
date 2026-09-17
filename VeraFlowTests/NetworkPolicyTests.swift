import Testing
import Foundation

@Suite("Network Policy & Privacy Enforcement Tests (§14.1)")
struct NetworkPolicyTests {
    @Test("Verify zero unauthorized network frameworks or APIs in app source files")
    func testZeroUnauthorizedNetworkCalls() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let appSourceDir = repoRoot.appendingPathComponent("VeraFlow")
        
        guard FileManager.default.fileExists(atPath: appSourceDir.path) else {
            return
        }
        
        let enumerator = FileManager.default.enumerator(at: appSourceDir, includingPropertiesForKeys: [.isRegularFileKey])
        var violations: [String] = []
        let forbiddenTerms = ["URLSession", "NWConnection", "CFNetwork", "WebSocketTask", "HTTPCookieStorage"]
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            
            let fileName = fileURL.lastPathComponent
            if fileName.contains("ModelDownload") || fileName.contains("AssetDownloader") {
                continue
            }
            
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            for term in forbiddenTerms {
                if content.contains(term) {
                    violations.append("\(fileURL.lastPathComponent) contains '\(term)'")
                }
            }
        }
        
        #expect(violations.isEmpty, "Found unauthorized network occurrences in: \(violations.joined(separator: ", "))")
    }
}
