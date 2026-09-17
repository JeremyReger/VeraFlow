import Testing
import Foundation
@testable import VeraFlow

@Suite("Capability, Storage, & Privacy Tests (§14, §15, §16 M7)")
struct CapabilityAndPrivacyTests {
    
    @Test("DeviceCapabilities honest messaging accurately reflects intelligence state (§15)")
    func testHonestCapabilityMessaging() {
        // 1. Device with Apple Intelligence
        let capFull = DeviceCapabilities(
            hasSpeechTranscriber: true,
            hasAppleIntelligence: true,
            isAppleIntelligenceDownloading: false
        )
        #expect(capFull.honestCapabilityMessage.contains("local Apple Intelligence summaries"))
        
        // 2. Device currently downloading models
        let capDownloading = DeviceCapabilities(
            hasSpeechTranscriber: true,
            hasAppleIntelligence: false,
            isAppleIntelligenceDownloading: true
        )
        #expect(capDownloading.honestCapabilityMessage.contains("downloading"))
        
        // 3. Device without Apple Intelligence (e.g. iPhone 15 and earlier)
        let capUnsupported = DeviceCapabilities(
            hasSpeechTranscriber: true,
            hasAppleIntelligence: false,
            isAppleIntelligenceDownloading: false
        )
        #expect(capUnsupported.honestCapabilityMessage == "Transcripts work on this iPhone; AI summaries need an Apple Intelligence–capable iPhone.")
    }
    
    @Test("CapabilityService evaluates storage and file statistics accurately (§8.3, §14)")
    func testStorageUsageCalculation() throws {
        let service = CapabilityService()
        
        // Ensure recordings dir exists
        let dir = AppConstants.recordingsDirectoryURL
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Create a temporary test recording file
        let testSubdir = dir.appendingPathComponent("test_session_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testSubdir, withIntermediateDirectories: true)
        
        let testAudioURL = testSubdir.appendingPathComponent("audio.caf")
        let dummyData = Data(repeating: 0xAB, count: 4096)
        try dummyData.write(to: testAudioURL)
        
        let stats = service.calculateStorageUsage()
        #expect(stats.recordingCount >= 1)
        #expect(stats.totalSizeBytes >= 4096)
        
        // Cleanup test dir
        try? FileManager.default.removeItem(at: testSubdir)
    }
    
    @Test("BiometricLockService evaluates biometry type cleanly without crashing (§14.4)")
    func testBiometricLockService() {
        let service = BiometricLockService()
        let type = service.biometryType()
        #expect(type == .faceID || type == .touchID || type == .none)
    }
    
    @Test("PrivacyInfo.xcprivacy exists and strictly conforms to zero-tracking policy (§14.1)")
    func testPrivacyManifestConformity() throws {
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let privacyManifestURL = repoRoot.appendingPathComponent("VeraFlow/PrivacyInfo.xcprivacy")
        
        #expect(FileManager.default.fileExists(atPath: privacyManifestURL.path), "PrivacyInfo.xcprivacy must exist in VeraFlow target")
        
        let data = try Data(contentsOf: privacyManifestURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            #expect(Bool(false), "PrivacyInfo.xcprivacy must be a valid property list dictionary")
            return
        }
        
        // 1. Zero Tracking
        let tracking = plist["NSPrivacyTracking"] as? Bool
        #expect(tracking == false, "NSPrivacyTracking must be false")
        
        // 2. Zero Tracking Domains
        let domains = plist["NSPrivacyTrackingDomains"] as? [String]
        #expect(domains?.isEmpty == true, "NSPrivacyTrackingDomains must be empty")
        
        // 3. Zero Collected Data Types
        let collected = plist["NSPrivacyCollectedDataTypes"] as? [Any]
        #expect(collected?.isEmpty == true, "NSPrivacyCollectedDataTypes must be empty (100% on-device)")
        
        // 4. File Timestamp API Justification
        let accessedAPIs = plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        #expect(accessedAPIs != nil)
        let timestampAPI = accessedAPIs?.first(where: { ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryFileTimestamp" })
        #expect(timestampAPI != nil, "Must declare NSPrivacyAccessedAPICategoryFileTimestamp")
        let reasons = timestampAPI?["NSPrivacyAccessedAPITypeReasons"] as? [String]
        #expect(reasons?.contains("C617.1") == true, "Must include reason C617.1 for file timestamp access")
    }
}
