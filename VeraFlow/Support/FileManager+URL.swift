import Foundation

extension FileManager {
    /// `fileExists(atPath:)` for a file URL. Uses the unencoded path, because `URL.path()`
    /// percent-encodes spaces ("Application%20Support") and the check silently fails on device.
    func fileExists(at url: URL) -> Bool {
        fileExists(atPath: url.path(percentEncoded: false))
    }
}
