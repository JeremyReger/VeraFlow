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
        case somethingNew
    }
}

private enum OtherError: Error {
    case timeout
}

struct LanguageModelErrorBridgeTests {
    @Test("Case names are read from the error's description, with or without the type prefix")
    func describing() {
        #expect(LanguageModelErrorBridge.kind(describing: "timeout(FoundationModels.LanguageModelError.Timeout(reason: \"x\"))") == .timeout)
        #expect(LanguageModelErrorBridge.kind(describing: "LanguageModelError.contextSizeExceeded(…)") == .contextSizeExceeded)
        #expect(LanguageModelErrorBridge.kind(describing: "rateLimited(FoundationModels.LanguageModelError.RateLimited())") == .rateLimited)
        #expect(LanguageModelErrorBridge.kind(describing: "refusal(…)") == .refusal)
        #expect(LanguageModelErrorBridge.kind(describing: "guardrailViolation(…)") == .guardrailViolation)
        #expect(LanguageModelErrorBridge.kind(describing: "unsupportedLanguageOrLocale(…)") == .unsupportedLanguageOrLocale)
        #expect(LanguageModelErrorBridge.kind(describing: "unsupportedTranscriptContent(…)") == .unsupported)
        #expect(LanguageModelErrorBridge.kind(describing: "Error Domain=FoundationModels.LanguageModelError Code=-1") == .unknown)
    }

    @Test("Only errors from a LanguageModelError type are bridged; other types are left alone")
    func domains() {
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.timeout("slow")) == .timeout)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.contextSizeExceeded(9)) == .contextSizeExceeded)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.rateLimited) == .rateLimited)
        #expect(LanguageModelErrorBridge.kind(of: FoundationModelsStandIn.LanguageModelError.somethingNew) == .unknown)
        #expect(LanguageModelErrorBridge.kind(of: OtherError.timeout) == nil)
        #expect(LanguageModelErrorBridge.kind(of: CancellationError()) == nil)
        let opaque = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        #expect(LanguageModelErrorBridge.kind(of: opaque) == .unknown)
    }
}
