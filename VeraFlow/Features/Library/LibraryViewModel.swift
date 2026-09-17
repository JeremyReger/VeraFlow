import Foundation
import Observation
import SwiftData

@Observable
public final class LibraryViewModel {
    public var searchText: String = ""
    public var selectedTag: String? = nil
    public var isRecordingPresented: Bool = false
    public var isSettingsPresented: Bool = false
    
    public init() {}
    
    public func filterRecordings(_ recordings: [Recording]) -> [Recording] {
        recordings.filter { recording in
            let matchesSearch = searchText.isEmpty ||
                recording.title.localizedCaseInsensitiveContains(searchText) ||
                recording.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            
            let matchesTag = selectedTag == nil || recording.tags.contains(selectedTag!)
            return matchesSearch && matchesTag
        }
    }
}
