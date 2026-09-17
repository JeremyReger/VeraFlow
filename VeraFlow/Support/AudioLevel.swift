import Foundation

/// Converts a linear peak sample (0...1) to a 0...1 meter value on a 60 dB scale.
enum AudioLevel {
    static let floorDecibels: Float = -60

    static func normalized(peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(peak)
        let scaled = (decibels - floorDecibels) / -floorDecibels
        return min(1, max(0, scaled))
    }
}
