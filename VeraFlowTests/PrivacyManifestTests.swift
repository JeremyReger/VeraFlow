import Foundation
import Testing

/// SPEC §14.1: the App Privacy label target is **Data Not Collected**, and a mismatch between what
/// the manifest declares and what the app does is a leading cause of rejection. `NetworkPolicyTests`
/// already makes "nothing leaves the device" a build failure; this makes the declaration itself one.
struct PrivacyManifestTests {
    private static func manifest() throws -> [String: Any] {
        let url = SourceTree.repoRoot.appending(path: "VeraFlow/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: Any], "PrivacyInfo.xcprivacy is not a dictionary")
    }

    @Test("The manifest still claims no tracking and no collected data")
    func dataNotCollected() throws {
        let manifest = try Self.manifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect(
            (manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true,
            "A collected data type here means the Nutrition Label can no longer say Data Not Collected"
        )
    }

    /// Source markers for the required-reason APIs → the category that must declare them. Apple
    /// rejects a build that reaches one of these without a declared reason, and the check runs the
    /// direction that matters: an API added later without its category fails here, not at review.
    private static let requiredReasons: [(markers: [String], category: String)] = [
        (["UserDefaults", "@AppStorage"], "NSPrivacyAccessedAPICategoryUserDefaults"),
        (["attributesOfItem", "contentModificationDate", ".creationDate"], "NSPrivacyAccessedAPICategoryFileTimestamp"),
        (["volumeAvailableCapacity", "systemFreeSize"], "NSPrivacyAccessedAPICategoryDiskSpace"),
        (["systemUptime", "mach_absolute_time"], "NSPrivacyAccessedAPICategorySystemBootTime"),
        (["activeInputModes"], "NSPrivacyAccessedAPICategoryActiveKeyboards"),
    ]

    @Test("Every required-reason API the app reaches is declared with a reason")
    func requiredReasonAPIsAreDeclared() throws {
        let manifest = try Self.manifest()
        let declared = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? []
        let categories = Set(declared.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        let sources = try SourceTree.appSourceFiles()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for entry in Self.requiredReasons where entry.markers.contains(where: { sources.contains($0) }) {
            #expect(categories.contains(entry.category), "The app reaches \(entry.category) but the manifest declares no reason for it")
        }
        // A declared category with no reason code is the same rejection as no declaration at all.
        for type in declared {
            let category = (type["NSPrivacyAccessedAPIType"] as? String) ?? "an unnamed category"
            #expect(
                (type["NSPrivacyAccessedAPITypeReasons"] as? [String])?.isEmpty == false,
                "\(category) is declared with no reason code"
            )
        }
    }
}
