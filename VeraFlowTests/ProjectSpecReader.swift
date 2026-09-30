import Foundation

/// Reads `project.yml` well enough to check what each target declares (SPEC §14.5). XcodeGen
/// writes every Info.plist from that file, so it — not a generated plist — is where a submission
/// claim has to be checked. A real YAML parser would be a second dependency for the sake of three
/// tests; the spec's shape is fixed and shallow, so a line scan over it is enough.
enum ProjectSpecReader {
    /// The app targets that compile all of `VeraFlow/`. Both need every usage string the shared
    /// sources imply, which is the whole point of checking them separately.
    static let appTargets = ["VeraFlow", "VeraFlow-macOS"]

    static func contents() throws -> String {
        try String(contentsOf: SourceTree.repoRoot.appending(path: "project.yml"), encoding: .utf8)
    }

    /// The lines belonging to one target: from its two-space-indented name under `targets:` to the
    /// next target's. `schemes:` at the foot of the file reuses the same names, so the scan stops
    /// at the first line that is flush left after `targets:`.
    static func lines(forTarget target: String) throws -> [String] {
        let all = try contents().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let targetsIndex = all.firstIndex(where: { $0 == "targets:" }) else { return [] }
        var collecting = false
        var lines: [String] = []
        for line in all[all.index(after: targetsIndex)...] {
            if !line.hasPrefix(" "), !line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if line.hasPrefix("  "), !line.hasPrefix("   "), line.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
                collecting = line.trimmingCharacters(in: .whitespaces) == "\(target):"
                continue
            }
            if collecting { lines.append(line) }
        }
        return lines
    }

    /// The `NS…UsageDescription` keys this target declares.
    static func usageDescriptionKeys(forTarget target: String) throws -> Set<String> {
        let pattern = /\b(NS[A-Za-z]+UsageDescription)\b/
        var keys: Set<String> = []
        for line in try lines(forTarget: target) {
            for match in line.matches(of: pattern) { keys.insert(String(match.1)) }
        }
        return keys
    }

    /// Every double-quoted string a target declares — the user-facing copy in its Info.plist.
    static func quotedStrings(forTarget target: String) throws -> [String] {
        let pattern = /"([^"]*)"/
        var strings: [String] = []
        for line in try lines(forTarget: target) {
            for match in line.matches(of: pattern) { strings.append(String(match.1)) }
        }
        return strings
    }
}
