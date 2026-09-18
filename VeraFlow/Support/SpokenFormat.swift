import Foundation

/// Text for VoiceOver labels and values, where "03:45" would be read as digits and "S2" as
/// letters (accessibility review A-2, A-12, A-29).
enum SpokenFormat {
    /// "3 minutes, 45 seconds". Whole seconds; hours appear only when needed.
    static func duration(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        Duration.seconds(max(0, seconds.rounded()))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale))
    }

    /// Display name for a raw speaker key when no speaker record exists: "S2" → "Speaker 2".
    static func speakerName(forKey key: String) -> String {
        if key.hasPrefix("S"), let number = Int(key.dropFirst()) {
            return "Speaker \(number)"
        }
        return key
    }
}
