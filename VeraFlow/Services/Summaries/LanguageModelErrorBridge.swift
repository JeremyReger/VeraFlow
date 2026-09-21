import Foundation

/// Recognises the iOS 27 `FoundationModels.LanguageModelError` cases at runtime by name.
///
/// This app builds with the iOS 26.5 SDK, which only knows `LanguageModelSession.GenerationError`.
/// On an iOS 27 phone the framework throws its new `LanguageModelError` instead, which this
/// binary can't name, so a `catch` for the old type misses it and the summary failed with
/// "LanguageModelError error -1". Until the Xcode 27 migration (M9), the case name in the
/// error's description is the only handle: e.g. "timeout(FoundationModels.LanguageModelError.Timeout(…))".
enum LanguageModelErrorBridge {
    enum Kind: Equatable, Sendable {
        case contextSizeExceeded
        /// The model's answer couldn't be parsed into the type. In practice it ran on and was cut
        /// off mid-JSON, so the text is incomplete rather than wrong.
        case decodingFailure
        case rateLimited
        case timeout
        case refusal
        case guardrailViolation
        case unsupportedLanguageOrLocale
        /// One of the "unsupported …" cases other than language: capability, transcript content, generation guide.
        case unsupported
        case unknown
    }

    /// `nil` when the error is neither a `LanguageModelError` nor a failure to build the answer.
    static func kind(of error: any Error) -> Kind? {
        let description = String(describing: error)
        if isLanguageModelErrorDomain((error as NSError).domain) {
            let named = kind(describing: description)
            guard named == .unknown else { return named }
            return isParseFailure(description) || isParseFailure(error.localizedDescription) ? .decodingFailure : .unknown
        }
        // Turning the answer into a `@Generable` type throws its own error type, outside the
        // `LanguageModelError` domain, so the name check above never sees it.
        return isParseFailure(description) || isParseFailure(error.localizedDescription) ? .decodingFailure : nil
    }

    /// The answer couldn't be built into the requested type.
    ///
    /// Seen on device 2026-09-21: "GeneratedContent does not contain a property 'startTimestamp'",
    /// thrown after the model's answer was cut off mid-array, leaving the last object short of a
    /// field. It reached the app as an unrecognised error, which the summarizer treated as fatal
    /// instead of running the retry that exists for exactly this.
    static func isParseFailure(_ description: String) -> Bool {
        let text = description.lowercased()
        return text.contains("does not contain a property")
            || text.contains("failed to parse generated content")
            || text.contains("generatedcontent")
    }

    static func isLanguageModelErrorDomain(_ domain: String) -> Bool {
        domain == "FoundationModels.LanguageModelError" || domain.hasSuffix(".LanguageModelError")
    }

    /// Matches the case name at the start of the description; order matters for the "unsupported…" family.
    static func kind(describing description: String) -> Kind {
        let text = description.lowercased()
        let name: String
        if let paren = text.firstIndex(of: "(") {
            name = String(text[..<paren]).trimmingCharacters(in: .whitespaces)
        } else {
            name = text.trimmingCharacters(in: .whitespaces)
        }
        // A fully qualified description ("LanguageModelError.timeout(…)") keeps only the last component.
        let caseName = name.split(separator: ".").last.map(String.init) ?? name
        switch caseName {
        case "contextsizeexceeded", "exceededcontextwindowsize": return .contextSizeExceeded
        case "decodingfailure": return .decodingFailure
        case "ratelimited": return .rateLimited
        case "timeout": return .timeout
        case "refusal": return .refusal
        case "guardrailviolation": return .guardrailViolation
        case "unsupportedlanguageorlocale": return .unsupportedLanguageOrLocale
        case "unsupportedcapability", "unsupportedtranscriptcontent", "unsupportedgenerationguide": return .unsupported
        default: return .unknown
        }
    }
}
