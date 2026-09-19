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
    /// v1.1: encoded `SummaryTranslations`, the payload's prose in other languages (plan item 14).
    var translationsJSON: Data?

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

    // MARK: Translations (v1.1 plan item 14)

    func translations() throws -> SummaryTranslations {
        guard let translationsJSON, !translationsJSON.isEmpty else { return [:] }
        return try JSONDecoder().decode(SummaryTranslations.self, from: translationsJSON)
    }

    /// The payload's prose in `language`, if it was translated.
    func translation(in language: String) -> SummaryPayload? {
        (try? translations())?[language]
    }

    /// Like `resolvedPayload()`, in `language`: the translated prose with the user's action-item
    /// edits applied (the edits are in whatever language the user typed).
    func resolvedTranslation(in language: String) throws -> SummaryPayload? {
        guard var payload = translation(in: language) else { return nil }
        payload.actionItems = payload.resolvedActionItems(applying: try actionItems())
        return payload
    }

    func storeTranslation(_ payload: SummaryPayload?, in language: String) throws {
        var all = try translations()
        all[language] = payload
        translationsJSON = all.isEmpty ? nil : try JSONEncoder().encode(all)
    }
}
