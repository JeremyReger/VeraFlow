import Foundation

/// What a library card shows for one recording (design spec §4 Library): a name the user gave
/// (or an imported file's name) always wins; the automatic "Meeting · date" title is replaced
/// by the summary's generated one. The gist is the summary overview, else the first transcript
/// line, and the pipeline state shows while it's still working.
struct LibraryCardModel: Equatable, Sendable {
    var title: String
    var snippet: String
    var timeOfDay: String
    var duration: String
    var speakerCount: Int
    var actionCount: Int
    var isFavorite: Bool
    var isImported: Bool
    /// The audio was removed to free space; the card says so next to the time.
    var isAudioRemoved: Bool
    /// The stage name while processing, or the failure text; `nil` when the recording is ready.
    var status: String?
    var isFailed: Bool

    init(recording: Recording, locale: Locale = .current) {
        let payload = try? recording.currentSummary?.payload()
        if recording.hasDefaultTitle, let generated = payload?.title, !generated.isEmpty {
            title = generated
        } else {
            title = recording.title
        }
        snippet = Self.snippet(
            overview: payload?.overview,
            firstTranscriptLine: recording.segments.min { $0.index < $1.index }?.text,
            stage: recording.stage
        )
        timeOfDay = recording.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        duration = Self.durationText(recording.duration)
        speakerCount = max(recording.speakers.count, recording.segments.isEmpty ? 0 : 1)
        actionCount = payload?.actionItems.count ?? 0
        isFavorite = recording.isFavorite
        isImported = recording.source == .imported
        isAudioRemoved = !recording.hasAudio
        switch recording.stage {
        case .ready where recording.failedStage == nil:
            status = nil
            isFailed = false
        case .failed:
            status = recording.failureMessage ?? "Failed"
            isFailed = true
        default:
            status = recording.failedStage != nil ? recording.failureMessage : recording.stage.displayName
            isFailed = false
        }
    }

    /// One clean sentence, at most ~140 characters, from the best source available.
    static func snippet(overview: String?, firstTranscriptLine: String?, stage: PipelineStage) -> String {
        let source = [overview, firstTranscriptLine]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let source else {
            return stage.hasTranscript ? "" : "Waiting to transcribe."
        }
        let collapsed = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > 140 else { return collapsed }
        let cut = collapsed.prefix(140)
        let trimmed = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        return trimmed + "…"
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// Recordings grouped under `TODAY`, `YESTERDAY`, or a date, in the order given.
struct LibrarySection: Identifiable, Equatable {
    var title: String
    var recordings: [Recording]
    var id: String { title }

    static func == (lhs: LibrarySection, rhs: LibrarySection) -> Bool {
        lhs.title == rhs.title && lhs.recordings.map(\.id) == rhs.recordings.map(\.id)
    }
}

enum LibraryGrouping {
    /// Groups by calendar day, keeping the incoming order inside each group. Only date sorts
    /// are grouped; title and length sorts get one untitled section.
    static func sections(_ recordings: [Recording], sort: LibrarySort, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> [LibrarySection] {
        guard sort == .newest || sort == .oldest else {
            return recordings.isEmpty ? [] : [LibrarySection(title: "", recordings: recordings)]
        }
        var sections: [LibrarySection] = []
        for recording in recordings {
            let title = Self.title(for: recording.createdAt, now: now, calendar: calendar, locale: locale)
            if let last = sections.indices.last, sections[last].title == title {
                sections[last].recordings.append(recording)
            } else {
                sections.append(LibrarySection(title: title, recordings: [recording]))
            }
        }
        return sections
    }

    static func title(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        var style = Date.FormatStyle(locale: locale, calendar: calendar).weekday(.wide).month(.abbreviated).day()
        if !sameYear { style = style.year() }
        return date.formatted(style)
    }
}
