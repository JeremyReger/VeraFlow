import Foundation

/// Where the user's marks sit between transcript paragraphs (v1.1 plan item 1): each mark shows
/// before the first listed paragraph that starts after it, or after the last paragraph.
enum TranscriptMarkers {
    /// Key: position in `segmentStarts` the marks go before (`segmentStarts.count` = after the
    /// last one). Value: indices into `markTimes`, in time order.
    static func placements(markTimes: [TimeInterval], segmentStarts: [TimeInterval]) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        let ordered = markTimes.indices.sorted { markTimes[$0] < markTimes[$1] }
        for markIndex in ordered {
            let time = markTimes[markIndex]
            let position = segmentStarts.firstIndex { $0 > time } ?? segmentStarts.count
            result[position, default: []].append(markIndex)
        }
        return result
    }
}
