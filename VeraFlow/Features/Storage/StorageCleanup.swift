import Foundation

/// One recording as the Storage screen sees it (Jeremy, 2026-09-19: "keep the summaries but
/// give the option to delete the audio files"). Pure, so the filters are unit-tested.
struct StorageItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var byteCount: Int64
    var hasSummary: Bool
    var stage: PipelineStage

    /// Audio can go once the transcript exists and nothing is still reading the file.
    var canRemoveAudio: Bool { Self.canRemoveAudio(stage: stage) }

    static func canRemoveAudio(stage: PipelineStage) -> Bool {
        stage.hasTranscript && stage != .diarizing
    }

    /// Why a row can't be selected, for the disabled row.
    var blockedReason: String? {
        if canRemoveAudio { return nil }
        return stage == .diarizing ? "Labeling speakers" : "Not transcribed yet"
    }
}

enum StorageSort: String, CaseIterable, Identifiable, Sendable {
    case largest
    case oldest
    case longest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .largest: "Largest first"
        case .oldest: "Oldest first"
        case .longest: "Longest first"
        }
    }
}

/// Which rows the Storage screen shows and in what order.
struct StorageFilter: Equatable, Sendable {
    var sort: StorageSort = .largest
    /// Only recordings at least this many days old; `nil` shows every one.
    var olderThanDays: Int? = nil
    var onlyWithSummary = false

    static let ageChoices = [30, 90, 180]

    func apply(to items: [StorageItem], now: Date = .now) -> [StorageItem] {
        var result = items.filter { item in
            if let days = olderThanDays, item.createdAt > now.addingTimeInterval(-Double(days) * 86_400) { return false }
            if onlyWithSummary, !item.hasSummary { return false }
            return true
        }
        switch sort {
        case .largest:
            result.sort { $0.byteCount == $1.byteCount ? $0.createdAt < $1.createdAt : $0.byteCount > $1.byteCount }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .longest:
            result.sort { $0.duration == $1.duration ? $0.createdAt < $1.createdAt : $0.duration > $1.duration }
        }
        return result
    }
}

enum StorageMath {
    static func totalBytes(_ items: [StorageItem]) -> Int64 {
        items.reduce(0) { $0 + $1.byteCount }
    }

    /// "28.4 MB", "1.2 GB": the file style users see in Files and Settings.
    static func text(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
