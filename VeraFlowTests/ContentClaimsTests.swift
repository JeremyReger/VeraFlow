import Foundation
import Testing

/// SPEC §14.3 and the product guardrails: no medical, legal or HIPAA claims in the app, the
/// listing, or the metadata. HIPAA compliance is a property of an organisation with a signed BAA,
/// never of a binary, so the claim would be false as well as a rejection risk — and a meeting
/// recorder is exactly the kind of app where such a line gets added with good intentions.
///
/// Comments are stripped before the scan: the sources are full of notes saying *not* to make these
/// claims, and those notes are the opposite of a violation.
struct ContentClaimsTests {
    private static let forbidden = [
        "hipaa", "medical", "patient", "legal advice", "attorney", "diagnosis", "diagnose",
    ]

    /// Everything but the `//` comments. Crude — it also truncates a `//` inside a string, which
    /// costs nothing here, since a URL is not where a medical claim hides.
    private static func withoutComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard let range = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<range.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("No app source claims anything medical, legal, or HIPAA")
    func sourcesMakeNoClaims() throws {
        var offenders: [String] = []
        for file in try SourceTree.appSourceFiles() {
            let text = Self.withoutComments(try String(contentsOf: file, encoding: .utf8)).lowercased()
            for word in Self.forbidden where text.contains(word) {
                offenders.append("\(file.lastPathComponent): \(word)")
            }
        }
        #expect(offenders.isEmpty, "Claims found in app copy: \(offenders)")
    }

    @Test("No Info.plist string claims anything medical, legal, or HIPAA", arguments: ProjectSpecReader.appTargets)
    func metadataMakesNoClaims(target: String) throws {
        var offenders: [String] = []
        for string in try ProjectSpecReader.quotedStrings(forTarget: target) {
            let lowered = string.lowercased()
            for word in Self.forbidden where lowered.contains(word) {
                offenders.append("\(word) in \"\(string)\"")
            }
        }
        #expect(offenders.isEmpty, "Claims found in \(target) metadata: \(offenders)")
    }
}
