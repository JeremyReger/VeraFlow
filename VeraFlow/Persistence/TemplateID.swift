import Foundation

/// The summary templates shipped in v1 (SPEC §3, §11.4).
enum TemplateID: String, Codable, Sendable, CaseIterable, Identifiable {
    case general
    case client
    case walkthrough

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: "General meeting / lecture"
        case .client: "Client / consulting meeting"
        case .walkthrough: "Contractor job walk-through"
        }
    }

    var shortName: String {
        switch self {
        case .general: "General"
        case .client: "Client"
        case .walkthrough: "Walk-through"
        }
    }
}
