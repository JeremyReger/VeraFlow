import Foundation
import Testing
@testable import VeraFlow

struct StorageCleanupTests {
    private let now = Date(timeIntervalSince1970: 1_789_040_000)

    private func item(_ title: String, daysAgo: Double, duration: TimeInterval, bytes: Int64, summary: Bool = true, stage: PipelineStage = .ready) -> StorageItem {
        StorageItem(id: UUID(), title: title, createdAt: now.addingTimeInterval(-daysAgo * 86_400), duration: duration, byteCount: bytes, hasSummary: summary, stage: stage)
    }

    @Test("Sorts by size, age or length, with ties broken by date")
    func sorting() {
        let items = [
            item("a", daysAgo: 1, duration: 600, bytes: 5_000_000),
            item("b", daysAgo: 40, duration: 3_600, bytes: 30_000_000),
            item("c", daysAgo: 100, duration: 1_200, bytes: 30_000_000),
        ]
        var filter = StorageFilter()
        #expect(filter.apply(to: items, now: now).map(\.title) == ["c", "b", "a"])
        filter.sort = .oldest
        #expect(filter.apply(to: items, now: now).map(\.title) == ["c", "b", "a"])
        filter.sort = .longest
        #expect(filter.apply(to: items, now: now).map(\.title) == ["b", "c", "a"])
    }

    @Test("Age and summary filters narrow the list")
    func filtering() {
        let items = [
            item("new", daysAgo: 1, duration: 60, bytes: 1),
            item("month", daysAgo: 31, duration: 60, bytes: 2, summary: false),
            item("quarter", daysAgo: 95, duration: 60, bytes: 3),
        ]
        var filter = StorageFilter()
        filter.olderThanDays = 30
        #expect(filter.apply(to: items, now: now).map(\.title) == ["quarter", "month"])
        filter.onlyWithSummary = true
        #expect(filter.apply(to: items, now: now).map(\.title) == ["quarter"])
        filter.olderThanDays = 90
        #expect(filter.apply(to: items, now: now).map(\.title) == ["quarter"])
        filter.olderThanDays = 180
        #expect(filter.apply(to: items, now: now).isEmpty)
    }

    @Test("Audio can be removed once a transcript exists and nothing is reading the file")
    func eligibility() {
        #expect(StorageItem.canRemoveAudio(stage: .ready))
        #expect(StorageItem.canRemoveAudio(stage: .transcribed))
        #expect(StorageItem.canRemoveAudio(stage: .summarizing))
        #expect(!StorageItem.canRemoveAudio(stage: .diarizing))
        #expect(!StorageItem.canRemoveAudio(stage: .recorded))
        #expect(!StorageItem.canRemoveAudio(stage: .transcribing))
        #expect(!StorageItem.canRemoveAudio(stage: .failed))
        #expect(item("x", daysAgo: 0, duration: 1, bytes: 1, stage: .diarizing).blockedReason == "Labeling speakers")
        #expect(item("x", daysAgo: 0, duration: 1, bytes: 1, stage: .recorded).blockedReason == "Not transcribed yet")
        #expect(item("x", daysAgo: 0, duration: 1, bytes: 1).blockedReason == nil)
    }

    @Test("Totals add up and format in the file style")
    func totals() {
        let items = [item("a", daysAgo: 0, duration: 1, bytes: 1_000_000), item("b", daysAgo: 0, duration: 1, bytes: 500_000)]
        #expect(StorageMath.totalBytes(items) == 1_500_000)
        #expect(StorageMath.text(bytes: 1_500_000) == "1.5 MB")
        #expect(StorageMath.text(bytes: 0) == "Zero KB")
    }
}
