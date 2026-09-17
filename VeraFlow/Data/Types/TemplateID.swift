import Foundation

/// Summary template identifier (§11.4)
public enum TemplateID: String, Codable, Sendable, CaseIterable, Identifiable {
    case general
    case client
    case walkthrough
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .general: "General Meeting / Lecture"
        case .client: "Client / Consulting Meeting"
        case .walkthrough: "Contractor Job Walk-Through"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .general: "Overview, key points, decisions, and clear action items."
        case .client: "Client goals, concerns, commitments, and follow-up draft."
        case .walkthrough: "Work areas, exact spoken measurements, materials, and quote notes."
        }
    }
}
