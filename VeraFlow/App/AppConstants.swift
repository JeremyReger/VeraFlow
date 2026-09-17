import Foundation

public enum AppConstants {
    /// Official product branding
    public static let appName = "VeraFlow"
    
    /// Internal / alpha / demo version codename
    public static let alphaCodename = "Riffle"
    
    /// Bundle identifiers
    public static let productionBundleID = "com.veraflow.app"
    public static let alphaBundleID = "com.veraflow.riffle"
    
    /// In-App Purchase Product Identifiers (§13)
    public static let lifetimeUnlockProductID = "veraflow.unlock.lifetime"
    public static let alphaLifetimeUnlockProductID = "riffle.unlock.lifetime"
    
    /// Free tier quota
    public static let freeSummaryLimit = 3
    
    /// Storage paths
    public static let recordingsDirectoryName = "Recordings"
    
    public static var recordingsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(recordingsDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Audio configuration defaults (§8)
    public static let sampleRate: Double = 44100.0
    public static let targetChannels: UInt32 = 1 // Mono
    public static let defaultBitRate: Int = 64000 // ~64 kbps AAC
}
