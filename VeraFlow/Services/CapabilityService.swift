import Foundation
import Speech
import FoundationModels

/// Production device capability monitor inspecting Speech, Foundation Models, and local storage (§15).
public final class CapabilityService: CapabilityServiceProtocol, Sendable {
    
    public init() {}
    
    public func currentCapabilities() async -> DeviceCapabilities {
        var hasSpeech = false
        var hasAppleIntelligence = false
        var isDownloading = false
        let isDiarizationReady = true
        var supportsBackgroundProcessing = true
        var tokenContextLimit = 4096
        
        // 1. Check SpeechTranscriber (§9.1)
        if #available(iOS 26.0, *) {
            hasSpeech = SpeechTranscriber.isAvailable
        }
        
        // 2. Check Foundation Models / Apple Intelligence (§11.1)
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            hasAppleIntelligence = true
            isDownloading = false
        case .unavailable(let reason):
            switch reason {
            case .modelNotReady:
                hasAppleIntelligence = false
                isDownloading = true
            default:
                hasAppleIntelligence = false
                isDownloading = false
            }
        @unknown default:
            hasAppleIntelligence = false
            isDownloading = false
        }
        
        // 3. Token Context Limit (§11.2)
        if #available(iOS 27.0, *) {
            tokenContextLimit = 8192
        } else {
            tokenContextLimit = 4096
        }
        
        // 4. Background Processing check
        #if targetEnvironment(simulator)
        supportsBackgroundProcessing = false
        #else
        supportsBackgroundProcessing = true
        #endif
        
        return DeviceCapabilities(
            hasSpeechTranscriber: hasSpeech,
            hasAppleIntelligence: hasAppleIntelligence,
            isAppleIntelligenceDownloading: isDownloading,
            isDiarizationReady: isDiarizationReady,
            supportsBackgroundProcessing: supportsBackgroundProcessing,
            estimatedTokenContextLimit: tokenContextLimit
        )
    }
    
    public func checkSpeechLocaleAvailability(locale: Locale) async -> Bool {
        if #available(iOS 26.0, *) {
            return await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil
        }
        return false
    }
    
    public func calculateStorageUsage() -> (recordingCount: Int, totalSizeBytes: Int64) {
        let dir = AppConstants.recordingsDirectoryURL
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: dir.path) else {
            return (0, 0)
        }
        
        var count = 0
        var totalBytes: Int64 = 0
        
        let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values.isDirectory == false {
                    if let size = values.fileSize {
                        totalBytes += Int64(size)
                    }
                    if ["caf", "m4a", "wav", "mp3"].contains(fileURL.pathExtension.lowercased()) {
                        count += 1
                    }
                }
            } catch {
                continue
            }
        }
        
        return (count, totalBytes)
    }
}
