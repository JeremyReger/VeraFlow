import Foundation
import Testing
@testable import VeraFlow

@MainActor
struct LibraryFilterTests {
    private func sample() -> [Recording] {
        let base = Date(timeIntervalSince1970: 1_789_000_000)
        return [
            Recording(title: "Kitchen remodel", createdAt: base, duration: 600, tags: ["contractor"], isFavorite: true),
            Recording(title: "Weekly client check-in", createdAt: base.addingTimeInterval(-3_600), duration: 1_800, tags: ["client"]),
            Recording(title: "Lecture on materials", createdAt: base.addingTimeInterval(-7_200), duration: 3_600),
            Recording(title: "another kitchen visit", createdAt: base.addingTimeInterval(60), duration: 30, tags: ["contractor", "Client"]),
        ]
    }

    @Test("Default is newest first")
    func newestFirst() {
        let titles = LibraryFilter().apply(to: sample()).map(\.title)
        #expect(titles == ["another kitchen visit", "Kitchen remodel", "Weekly client check-in", "Lecture on materials"])
    }

    @Test("Sort options")
    func sorts() {
        var filter = LibraryFilter()
        filter.sort = .oldest
        #expect(filter.apply(to: sample()).first?.title == "Lecture on materials")
        filter.sort = .longest
        #expect(filter.apply(to: sample()).first?.title == "Lecture on materials")
        filter.sort = .title
        #expect(filter.apply(to: sample()).map(\.title) == ["another kitchen visit", "Kitchen remodel", "Lecture on materials", "Weekly client check-in"])
    }

    @Test("Search matches titles case-insensitively and ignores surrounding whitespace")
    func search() {
        var filter = LibraryFilter()
        filter.searchText = "  kitchen "
        #expect(filter.apply(to: sample()).map(\.title) == ["another kitchen visit", "Kitchen remodel"])
        #expect(filter.isNarrowing)
        filter.searchText = "zzz"
        #expect(filter.apply(to: sample()).isEmpty)
    }

    @Test("Search needs every word, anywhere in the title, summary, tags, or transcript")
    func matchesFields() {
        let fields = ["Meeting · Sep 18, 2026", "Kitchen remodel walk-through", "The permit must be in hand", "contractor"]
        #expect(LibraryFilter.matches(query: "permit", in: fields))
        #expect(LibraryFilter.matches(query: "kitchen permit", in: fields))
        #expect(LibraryFilter.matches(query: "CONTRACTOR", in: fields))
        #expect(!LibraryFilter.matches(query: "kitchen plumbing", in: fields))
        #expect(LibraryFilter.matches(query: "", in: fields))

        let recording = Recording(title: "Site visit", tags: ["roof"])
        #expect(LibraryFilter.searchableText(for: recording) == ["Site visit", "roof"])
    }

    @Test("Favorites and tag filters combine with search")
    func favoritesAndTags() {
        var filter = LibraryFilter()
        filter.favoritesOnly = true
        #expect(filter.apply(to: sample()).map(\.title) == ["Kitchen remodel"])

        filter = LibraryFilter()
        filter.tag = "contractor"
        #expect(filter.apply(to: sample()).count == 2)
        filter.searchText = "visit"
        #expect(filter.apply(to: sample()).map(\.title) == ["another kitchen visit"])
        #expect(!LibraryFilter().isNarrowing)
    }

    @Test("All tags are unique and sorted")
    func allTags() {
        #expect(LibraryFilter.allTags(in: sample()) == ["client", "Client", "contractor"] || LibraryFilter.allTags(in: sample()) == ["Client", "client", "contractor"])
    }
}
