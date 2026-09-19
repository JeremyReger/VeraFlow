import Foundation
import Translation

/// Apple's Translation framework (iOS 18+): language availability and the per-session
/// translator (v1.1 plan item 14). Everything runs on device; the language packs are Apple
/// asset downloads managed by iOS (SPEC §14.1).
///
/// Compiled against the iOS 26.5 SDK on 2026-09-19: `LanguageAvailability.supportedLanguages`, `status(from:to:)`,
/// `TranslationSession.translations(from:)`, `TranslationSession.Request(sourceText:clientIdentifier:)`.
struct LiveTranslationService: TranslationService {
    func targets(from source: Locale.Language) async -> [Locale.Language] {
        let availability = LanguageAvailability()
        let supported = await availability.supportedLanguages
        var targets: [Locale.Language] = []
        for language in supported where !TranslationLanguages.isSame(language, source) {
            // One entry per language, not per region.
            guard !targets.contains(where: { TranslationLanguages.isSame($0, language) }) else { continue }
            let status = await availability.status(from: source, to: language)
            if status != .unsupported {
                targets.append(language)
            }
        }
        return targets.sorted { TranslationLanguages.name(for: $0) < TranslationLanguages.name(for: $1) }
    }

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability {
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed: .installed
        case .supported: .needsDownload
        case .unsupported: .unsupported
        @unknown default: .unsupported
        }
    }
}

/// Wraps the session SwiftUI hands to `translationTask`. The session is only used from the
/// main actor inside that task's closure, which is why the wrapper can promise `Sendable`.
struct LiveTextTranslator: TextTranslator, @unchecked Sendable {
    let session: TranslationSession

    func translate(_ requests: [TranslationRequest]) async throws -> [TranslationResult] {
        let batch = requests.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
        let responses = try await session.translations(from: batch)
        return responses.compactMap { response in
            guard let id = response.clientIdentifier else { return nil }
            return TranslationResult(id: id, text: response.targetText)
        }
    }
}
