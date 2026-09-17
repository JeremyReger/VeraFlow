import Foundation
import Observation
import SwiftData

public enum LibrarySortOption: String, CaseIterable, Identifiable, Sendable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"
    case longestDuration = "Longest Duration"
    case shortestDuration = "Shortest Duration"
    case alphabetical = "Title (A–Z)"
    
    public var id: String { rawValue }
}

@Observable
public final class LibraryViewModel {
    public var searchText: String = ""
    public var selectedTag: String? = nil
    public var showFavoritesOnly: Bool = false
    public var sortOption: LibrarySortOption = .newestFirst
    
    public var isRecordingPresented: Bool = false
    public var isSettingsPresented: Bool = false
    public var isFileImporterPresented: Bool = false
    
    public var recordingToRename: Recording? = nil
    public var renameTitleText: String = ""
    public var isRenameAlertPresented: Bool = false
    
    public var importErrorMessage: String? = nil
    public var importSuccessNotice: String? = nil
    
    public init() {}
    
    public func extractAllTags(from recordings: [Recording]) -> [String] {
        var tagsSet = Set<String>()
        for r in recordings {
            for t in r.tags {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    tagsSet.insert(trimmed)
                }
            }
        }
        return Array(tagsSet).sorted()
    }
    
    public func filterAndSortRecordings(_ recordings: [Recording]) -> [Recording] {
        // 1. Filter
        let filtered = recordings.filter { recording in
            // Search text filter
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                let query = searchText.lowercased()
                let titleMatch = recording.title.lowercased().contains(query)
                let tagMatch = recording.tags.contains { $0.lowercased().contains(query) }
                let failureMatch = recording.failureMessage?.lowercased().contains(query) ?? false
                matchesSearch = titleMatch || tagMatch || failureMatch
            }
            
            // Tag filter
            let matchesTag: Bool
            if let selected = selectedTag {
                matchesTag = recording.tags.contains(selected)
            } else {
                matchesTag = true
            }
            
            // Favorites filter
            let matchesFavorites = !showFavoritesOnly || recording.isFavorite
            
            return matchesSearch && matchesTag && matchesFavorites
        }
        
        // 2. Sort
        return filtered.sorted { a, b in
            switch sortOption {
            case .newestFirst:
                return a.createdAt > b.createdAt
            case .oldestFirst:
                return a.createdAt < b.createdAt
            case .longestDuration:
                return a.duration > b.duration
            case .shortestDuration:
                return a.duration < b.duration
            case .alphabetical:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }
    
    public func promptRename(for recording: Recording) {
        recordingToRename = recording
        renameTitleText = recording.title
        isRenameAlertPresented = true
    }
    
    public func applyRename() {
        guard let recording = recordingToRename else { return }
        let trimmed = renameTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            recording.title = trimmed
        }
        recordingToRename = nil
        renameTitleText = ""
    }
}
