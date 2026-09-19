import Foundation
import Observation
import SwiftData

/// Drives "Translate to…" on the detail screen (v1.1 plan item 14). The view asks for a
/// language; `TranslationHost` turns that into a `TranslationSession` and calls `run`, which
/// translates the paragraphs and the current summary's prose in batches and stores the result
/// so it survives relaunch. Nothing here talks to the framework, so it is unit-tested with fakes.
@Observable
@MainActor
final class TranslationController {
    enum Phase: Equatable, Sendable {
        case idle
        case translating(done: Int, total: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The language the host should open a session for; cleared when the run ends.
    private(set) var pendingLanguage: String?
    /// Bumped on every request so the host re-runs its task even for the same language.
    private(set) var requestID = 0
    /// The translated text is shown in place of the original; "Show original" flips it.
    var showsTranslation = true

    var isTranslating: Bool {
        if case .translating = phase { return true }
        return false
    }

    /// Asks for a translation into `language` (BCP-47).
    func request(_ language: String) {
        guard !isTranslating else { return }
        pendingLanguage = language
        requestID += 1
        showsTranslation = true
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase { phase = .idle }
    }

    /// Translates every paragraph and the current summary into `pendingLanguage`. Paragraphs
    /// already in that language are skipped, so a failed run resumes where it stopped.
    func run(recording: Recording, context: ModelContext, translator: any TextTranslator) async {
        guard let language = pendingLanguage else { return }
        defer { pendingLanguage = nil }
        let segments = recording.orderedSegments.filter { $0.translation(in: language) == nil }
        let record = recording.currentSummary
        let summaryPayload = record.flatMap { record -> SummaryPayload? in
            record.translation(in: language) == nil ? try? record.payload() : nil
        }
        let summaryStrings = summaryPayload.map(SummaryTranslation.strings(of:)) ?? []
        let requests = TranslationBatcher.requests(segments.map(\.text), prefix: "p") + TranslationBatcher.requests(summaryStrings, prefix: "s")
        let batches = TranslationBatcher.batches(requests)
        guard !batches.isEmpty else {
            phase = .idle
            return
        }
        phase = .translating(done: 0, total: batches.count)
        var results: [TranslationResult] = []
        do {
            for (index, batch) in batches.enumerated() {
                results += try await translator.translate(batch)
                phase = .translating(done: index + 1, total: batches.count)
                // Paragraphs are stored as they come back, so a stop halfway keeps its work.
                store(results, into: segments, language: language)
                try context.save()
            }
            if let summaryPayload, let record {
                let translated = TranslationBatcher.merge(results, into: summaryStrings, prefix: "s")
                try record.storeTranslation(SummaryTranslation.applying(translated, to: summaryPayload), in: language)
                try context.save()
            }
            AppPreferences.setTranslationLanguage(language)
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    /// Removes the translation from the paragraphs and every summary.
    func remove(from recording: Recording, context: ModelContext) {
        for segment in recording.segments {
            segment.translatedText = nil
            segment.translationLanguage = nil
        }
        for record in recording.summaries {
            record.translationsJSON = nil
        }
        try? context.save()
        phase = .idle
    }

    private func store(_ results: [TranslationResult], into segments: [TranscriptSegment], language: String) {
        let byID = Dictionary(results.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        for (position, segment) in segments.enumerated() {
            guard let text = byID["p" + String(position)], segment.translation(in: language) == nil else { continue }
            segment.translatedText = text
            segment.translationLanguage = language
        }
    }

    static func message(for error: Error) -> String {
        if case TranslationFailure.message(let text) = error { return text }
        let description = error.localizedDescription
        return description.isEmpty ? "The translation stopped. Try again." : description
    }
}
