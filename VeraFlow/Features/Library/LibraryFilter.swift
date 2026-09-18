import Foundation

/// How the Library list is ordered.
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case title
    case longest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .title: "Title"
        case .longest: "Longest first"
        }
    }
}

/// Search, sort, and filter state for the Library (SPEC §3, M2). Pure so it can be unit tested.
struct LibraryFilter: Equatable, Sendable {
    var searchText = ""
    var sort: LibrarySort = .newest
    var favoritesOnly = false
    var tag: String?
    /// Filter chip for one summary template (design spec: "the user's own template names").
    var template: TemplateID?

    /// True when anything other than the default ordering is applied.
    var isNarrowing: Bool {
        !trimmedSearch.isEmpty || favoritesOnly || tag != nil || template != nil
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func apply(to recordings: [Recording]) -> [Recording] {
        let query = trimmedSearch
        var result = recordings.filter { recording in
            if favoritesOnly, !recording.isFavorite { return false }
            if let tag, !recording.tags.contains(tag) { return false }
            if let template, recording.templateID != template { return false }
            if !query.isEmpty, !Self.matches(query: query, in: Self.searchableText(for: recording)) { return false }
            return true
        }
        switch sort {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .longest:
            result.sort { $0.duration > $1.duration }
        }
        return result
    }

    /// True when every word of `query` appears somewhere in `fields` (case- and diacritic-insensitive).
    static func matches(query: String, in fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { word in
            fields.contains { $0.localizedStandardContains(word) }
        }
    }

    /// What search looks through: the stored title, the generated title and gist, the tags, and
    /// the transcript text. Recorded once per recording per keystroke; fine for a personal library.
    static func searchableText(for recording: Recording) -> [String] {
        var fields = [recording.title]
        if let payload = try? recording.currentSummary?.payload() {
            fields.append(payload.title)
            fields.append(payload.overview)
        }
        fields.append(contentsOf: recording.tags)
        fields.append(contentsOf: recording.segments.map(\.text))
        return fields
    }

    /// Every distinct tag in use, alphabetically.
    static func allTags(in recordings: [Recording]) -> [String] {
        Array(Set(recordings.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
