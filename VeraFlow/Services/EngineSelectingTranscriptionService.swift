import Foundation

/// Routes each call to Apple's engine or Parakeet according to a stored preference, so the
/// benchmark screen can switch engines without rebuilding the pipeline (SPEC §9.4).
/// Only debug builds on iOS 26 use it; release builds use one engine (Apple's on iOS 26,
/// Parakeet on iOS 18–25, v1.1 plan item 16).
actor EngineSelectingTranscriptionService: TranscriptionService {
    enum Choice: String, Sendable, CaseIterable {
        case apple
        case parakeet

        var displayName: String {
            switch self {
            case .apple: "Apple Speech"
            case .parakeet: "Parakeet (FluidAudio)"
            }
        }
    }

    static let preferenceKey = "transcription.engine"

    private let apple: any TranscriptionService
    private let parakeet: any TranscriptionService
    private let defaults: UserDefaults

    init(apple: any TranscriptionService, parakeet: any TranscriptionService, defaults: UserDefaults = .standard) {
        self.apple = apple
        self.parakeet = parakeet
        self.defaults = defaults
    }

    static func choice(in defaults: UserDefaults = .standard) -> Choice {
        Choice(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .apple
    }

    static func setChoice(_ choice: Choice, in defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: preferenceKey)
    }

    private var current: any TranscriptionService {
        switch Self.choice(in: defaults) {
        case .apple: apple
        case .parakeet: parakeet
        }
    }

    func isAvailable() async -> Bool { await current.isAvailable() }

    func supportedLocales() async -> [Locale] { await current.supportedLocales() }

    func assetStatus(for locale: Locale) async -> TranscriptionAssetStatus {
        await current.assetStatus(for: locale)
    }

    func prepareAssets(for locale: Locale, progress: @Sendable @escaping (Double) -> Void) async throws {
        try await current.prepareAssets(for: locale, progress: progress)
    }

    func transcribe(
        fileURL: URL,
        locale: Locale,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> TranscriptionResult {
        try await current.transcribe(fileURL: fileURL, locale: locale, progress: progress)
    }
}
