import Foundation
import Testing
@testable import VeraFlow

/// Stands in for the iOS 27 `FoundationModels.LanguageModelError` this SDK can't name; the
/// nesting gives the NSError domain the same ".LanguageModelError" suffix.
enum FoundationModelsStandIn {
    enum LanguageModelError: Error {
        case timeout(String)
        case contextSizeExceeded(Int)
        case rateLimited
        case decodingFailure(String)
        case somethingNew
    }
}

private enum OtherError: Error {
    case timeout
}

/// Stands in for the error thrown while building the answer into a `@Generable` type. It has its
/// own domain, outside `LanguageModelError`, which is how it slipped past the bridge on device.
private struct GeneratedContentStandIn: Error, CustomStringConvertible {
    var description: String
}

struct LanguageModelErrorBridgeTests {
    @Test("Case names are read from the error's description, with or without the type prefix")
    func describing() {
        #expect(LanguageModelErrorBridge.kind(describing: "timeout(FoundationModels.LanguageModelError.Timeout(reason: \"x\"))") == .timeout)
        #expect(LanguageModelErrorBridge.kind(describing: "LanguageModelError.contextSizeExceeded(…)") == .contextSizeExceeded)
        // The one that took Jeremy's 1:58 recording down: the answer looped until it was cut off
        // mid-JSON, and an unrecognised case name meant no retry at all (2026-09-19).
        #expect(LanguageModelErrorBridge.kind(describing: "decodingFailure(FoundationModels.LanguageModelError.Context(debugDescription: \"Failed to convert text\"))") == .decodingFailure)
        #expect(LanguageModelErrorBridge.kind(describing: "rateLimited(FoundationModels.LanguageModelError.RateLimited())") == .rateLimited)
        #expect(LanguageModelErrorBridge.kind(describing: "refusal(…)") == .refusal)
        #expect(LanguageModelErrorBridge.kind(describing: "guardrailViolation(…)") == .guardrailViolation)
        #expect(LanguageModelErrorBridge.kind(describing: "unsupportedLanguageOrLocale(…)") == .unsupportedLanguageOrLocale)
        #expect(LanguageModelErrorBridge.kind(describing: "unsupportedTranscriptContent(…)") == .unsupported)
        #expect(LanguageModelErrorBridge.kind(describing: "Error Domain=FoundationModels.LanguageModelError Code=-1") == .unknown)
        // iOS 26 spells the overflow the other way round; either name means the same thing.
        #expect(LanguageModelErrorBridge.kind(describing: "exceededContextWindowSize(…)") == .contextSizeExceeded)
    }

    /// The 39-minute meeting that wouldn't summarize (2026-09-21). The model's answer ran to its
    /// cap and stopped mid-array, so the last topic had no `startTimestamp` and the framework
    /// threw while building the type. It isn't a `LanguageModelError`, so the name check never saw
    /// it, it was treated as fatal, and the retry that exists for a cut-off answer never ran.
    @Test("An answer that won't build into the type reads as a decoding failure, whatever threw it")
    func parseFailures() {
        let onDevice = GeneratedContentStandIn(description: "GeneratedContent does not contain a property 'startTimestamp'.")
        #expect(LanguageModelErrorBridge.kind(of: onDevice) == .decodingFailure)
        #expect(LanguageModelErrorBridge.isParseFailure("Failed to parse generated content.") == true)
        #expect(LanguageModelErrorBridge.isParseFailure("GeneratedContent does not contain a property 'points'") == true)
        #expect(LanguageModelErrorBridge.isParseFailure("the network is unavailable") == false)
        // A LanguageModelError whose name we don't know, but whose text says it couldn't parse.
        let named = NSError(
            domain: "FoundationModels.LanguageModelError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to parse generated content."]
        )
        #expect(LanguageModelErrorBridge.kind(of: named) == .decodingFailure)
        // Still nothing to say about errors that aren't the model's.
        #expect(LanguageModelErrorBridge.kind(of: OtherError.timeout) == nil)
    }

    @Test("Only errors from a LanguageModelError type are bridged; other types are left alone")
    func domains() {
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.timeout("slow")) == .timeout)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.contextSizeExceeded(9)) == .contextSizeExceeded)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.rateLimited) == .rateLimited)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.decodingFailure("cut off")) == .decodingFailure)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.somethingNew) == .unknown)
        #expect(LanguageModelErrorBridge.kind(of: OtherError.timeout) == nil)
        #expect(LanguageModelErrorBridge.kind(of: CancellationError()) == nil)
        let opaque = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        #expect(LanguageModelErrorBridge.kind(of: opaque) == .unknown)
    }
}
