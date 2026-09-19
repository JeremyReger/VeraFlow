import Foundation

/// One string to translate, keyed so the answer maps back to where it came from
/// (v1.1 plan item 14).
struct TranslationRequest: Sendable, Equatable {
    var id: String
    var text: String
}

struct TranslationResult: Sendable, Equatable {
    var id: String
    var text: String
}

/// Whether this iPhone can translate one language into another.
enum TranslationAvailability: Sendable, Equatable {
    /// The language pack is on the phone.
    case installed
    /// Supported; iOS downloads the pack (an Apple asset, SPEC §14.1) the first time.
    case needsDownload
    case unsupported
}

/// What the app asks the Translation framework outside a session: which languages a recording
/// can be translated into. Translating itself needs a `TranslationSession`, which only exists
/// inside SwiftUI's `translationTask`, so that part goes through `TextTranslator`.
protocol TranslationService: Sendable {
    /// Languages this iPhone can translate `source` into, the source itself left out, sorted by
    /// display name.
    func targets(from source: Locale.Language) async -> [Locale.Language]
    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability
}

/// Translates one batch of strings. `LiveTextTranslator` wraps a `TranslationSession`.
protocol TextTranslator: Sendable {
    func translate(_ requests: [TranslationRequest]) async throws -> [TranslationResult]
}

/// Pure batching and mapping so the session sees only non-empty text and every answer lands
/// back on the string it came from, whatever order the framework returns it in.
enum TranslationBatcher {
    /// Requests per session call; progress is reported per batch.
    static let batchSize = 32

    /// One request per non-blank text, its id the text's position (with `prefix`).
    static func requests(_ texts: [String], prefix: String = "") -> [TranslationRequest] {
        texts.enumerated().compactMap { index, text in
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TranslationRequest(id: prefix + String(index), text: text)
        }
    }

    /// Writes results back by id. A text with no result (blank, or missing from the answer)
    /// keeps its original; order is the order of `texts`.
    static func merge(_ results: [TranslationResult], into texts: [String], prefix: String = "") -> [String] {
        let byID = Dictionary(results.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        return texts.enumerated().map { index, text in
            byID[prefix + String(index)] ?? text
        }
    }

    /// Splits requests into session-sized batches, order kept.
    static func batches(_ requests: [TranslationRequest], size: Int = batchSize) -> [[TranslationRequest]] {
        guard size > 0 else { return [requests] }
        return stride(from: 0, to: requests.count, by: size).map { Array(requests[$0..<min($0 + size, requests.count)]) }
    }
}

/// Display helpers for a target language stored as a BCP-47 identifier.
enum TranslationLanguages {
    /// "Spanish" in the display locale, falling back to the identifier.
    static func name(for identifier: String, displayLocale: Locale = .current) -> String {
        displayLocale.localizedString(forIdentifier: identifier) ?? identifier
    }

    static func name(for language: Locale.Language, displayLocale: Locale = .current) -> String {
        name(for: language.minimalIdentifier, displayLocale: displayLocale)
    }

    /// The recording's spoken language.
    static func source(of localeIdentifier: String) -> Locale.Language {
        Locale(identifier: localeIdentifier).language
    }

    /// Same language regardless of region ("en-US" and "en-GB" are one language here).
    static func isSame(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        lhs.languageCode?.identifier == rhs.languageCode?.identifier
    }
}

// MARK: - Fakes

/// Offers a fixed set of targets; every pair is installed.
struct FakeTranslationService: TranslationService {
    var languages: [Locale.Language] = ["es", "fr", "de", "en"].map { Locale.Language(identifier: $0) }
    var status: TranslationAvailability = .installed

    func targets(from source: Locale.Language) async -> [Locale.Language] {
        languages.filter { !TranslationLanguages.isSame($0, source) }
    }

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability {
        TranslationLanguages.isSame(source, target) ? .unsupported : status
    }
}

/// Prefixes every text with the language tag, e.g. "[es] Hello", so tests can see what moved.
struct FakeTextTranslator: TextTranslator {
    var tag = "es"
    var failure: String?

    func translate(_ requests: [TranslationRequest]) async throws -> [TranslationResult] {
        if let failure { throw TranslationFailure.message(failure) }
        return requests.map { TranslationResult(id: $0.id, text: "[\(tag)] \($0.text)") }
    }
}

enum TranslationFailure: Error, Equatable {
    case message(String)
}
