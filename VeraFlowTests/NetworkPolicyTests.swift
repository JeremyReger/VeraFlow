import Foundation
import Testing

/// SPEC §6.2: no network code in app targets outside the allow-listed ModelDownload file.
struct NetworkPolicyTests {
    /// Source patterns that indicate networking. Kept deliberately broad.
    private static let forbiddenPatterns = [
        "URLSession",
        "NWConnection",
        "NWListener",
        "import Network\n",
        "CFNetwork",
        "NSURLConnection",
    ]

    private static let allowedFiles: Set<String> = ["ModelDownload.swift"]

    @Test("App sources contain no networking outside ModelDownload.swift")
    func noNetworkingInAppSources() throws {
        let appSources = try SourceTree.appSourceFiles()
        #expect(!appSources.isEmpty, "Expected to find Swift sources under VeraFlow/")

        var offenders: [String] = []
        for file in appSources where !Self.allowedFiles.contains(file.lastPathComponent) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for pattern in Self.forbiddenPatterns where contents.contains(pattern) {
                offenders.append("\(file.lastPathComponent): \(pattern.trimmingCharacters(in: .newlines))")
            }
        }
        #expect(offenders.isEmpty, "Networking found outside the allow list: \(offenders)")
    }

    @Test("Third-party dependencies are limited to FluidAudio")
    func onlyFluidAudioDependency() throws {
        let projectFile = SourceTree.repoRoot.appending(path: "project.yml")
        let contents = try String(contentsOf: projectFile, encoding: .utf8)
        let packageURLs = contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("url:") }
        #expect(packageURLs.count == 1, "Any new package needs a written reason in docs/DECISIONS.md: \(packageURLs)")
        #expect(packageURLs.first?.contains("FluidInference/FluidAudio") == true)
    }
}

/// Locates the repo from this test file's compile-time path.
enum SourceTree {
    static var repoRoot: URL {
        // .../VeraFlowTests/NetworkPolicyTests.swift → repo root
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func appSourceFiles() throws -> [URL] {
        let appDirectory = repoRoot.appending(path: "VeraFlow", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: appDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}
