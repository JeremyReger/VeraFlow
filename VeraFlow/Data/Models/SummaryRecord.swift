import Foundation
import SwiftData

/// Represents an AI-generated summary record with action items and history (§7, §11)
@Model
public final class SummaryRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var templateIDRawValue: String
    public var payloadJSON: Data       // Encoded template output struct
    public var actionItemsState: Data  // Checkbox completion states, reminder IDs
    public var modelInfo: String       // e.g. "SystemLanguageModel iOS 26.5"
    
    public var templateID: TemplateID {
        get { TemplateID(rawValue: templateIDRawValue) ?? .general }
        set { templateIDRawValue = newValue.rawValue }
    }
    
    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        templateID: TemplateID = .general,
        payloadJSON: Data = Data(),
        actionItemsState: Data = Data(),
        modelInfo: String = "SystemLanguageModel"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.templateIDRawValue = templateID.rawValue
        self.payloadJSON = payloadJSON
        self.actionItemsState = actionItemsState
        self.modelInfo = modelInfo
    }
}

/// Action item extracted from transcription summary (§11.4)
public struct ActionItem: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var task: String
    public var owner: String
    public var speakerKey: String?
    public var dueText: String
    public var resolvedDueDate: Date?
    public var timestamp: String
    public var audioTime: TimeInterval?
    public var isCompleted: Bool
    public var reminderIdentifier: String?
    
    public init(
        id: UUID = UUID(),
        task: String,
        owner: String = "",
        speakerKey: String? = nil,
        dueText: String = "",
        resolvedDueDate: Date? = nil,
        timestamp: String = "",
        audioTime: TimeInterval? = nil,
        isCompleted: Bool = false,
        reminderIdentifier: String? = nil
    ) {
        self.id = id
        self.task = task
        self.owner = owner
        self.speakerKey = speakerKey
        self.dueText = dueText
        self.resolvedDueDate = resolvedDueDate
        self.timestamp = timestamp
        self.audioTime = audioTime
        self.isCompleted = isCompleted
        self.reminderIdentifier = reminderIdentifier
    }
}
