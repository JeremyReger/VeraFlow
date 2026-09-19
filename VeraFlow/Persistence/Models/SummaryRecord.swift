import Foundation
import SwiftData

/// One generated summary (SPEC §7). A recording keeps a history; the newest is current.
@Model
final class SummaryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var templateID: TemplateID
    /// Encoded `SummaryPayload` (SPEC §11.4).
    var payloadJSON: Data
    /// Encoded `ActionItemsState`: completion checkboxes and created reminder IDs.
    var actionItemsState: Data
    /// e.g. "SystemLanguageModel iOS 27.0 · prompt v1"
    var modelInfo: String
    /// v1.1: the custom template this summary was made with, if any (plan item 13).
    var customTemplateID: UUID?
    /// v1.1: the focus line it was told (plan item 13).
    var focus: String = ""

    var recording: Recording?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        templateID: TemplateID,
        payloadJSON: Data,
        actionItemsState: Data = Data(),
        modelInfo: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.templateID = templateID
        self.payloadJSON = payloadJSON
        self.actionItemsState = actionItemsState
        self.modelInfo = modelInfo
    }

    /// Decodes the stored payload.
    func payload() throws -> SummaryPayload {
        try JSONDecoder().decode(SummaryPayload.self, from: payloadJSON)
    }

    /// Decodes the stored action-item state; empty data decodes to a fresh state.
    func actionItems() throws -> ActionItemsState {
        guard !actionItemsState.isEmpty else { return ActionItemsState() }
        return try JSONDecoder().decode(ActionItemsState.self, from: actionItemsState)
    }

    /// The payload with the user's action-item edits applied (v1.1 plan item 2), for exports,
    /// Reminders and the library card.
    func resolvedPayload() throws -> SummaryPayload {
        var payload = try payload()
        payload.actionItems = payload.resolvedActionItems(applying: try actionItems())
        return payload
    }

    /// Persists a changed state.
    func store(_ state: ActionItemsState) throws {
        actionItemsState = try JSONEncoder().encode(state)
    }
}
