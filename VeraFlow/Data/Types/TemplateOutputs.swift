import Foundation
import FoundationModels

/// Raw action item extracted by Foundation Models (§11.4).
@Generable
public struct RawActionItem: Codable, Sendable, Equatable {
    @Guide(description: "Specific task or action item starting with an action verb")
    public var task: String
    
    @Guide(description: "Spoken name, speaker key (e.g. S1, S2), or role of person assigned")
    public var owner: String
    
    @Guide(description: "Colloquial or explicit due date mentioned in the audio (e.g. 'by Friday', 'Oct 15')")
    public var dueText: String
    
    @Guide(description: "Approximate audio timestamp where this item was discussed, formatted as mm:ss (e.g. '04:15')")
    public var timestamp: String
    
    public init(task: String = "", owner: String = "", dueText: String = "", timestamp: String = "") {
        self.task = task
        self.owner = owner
        self.dueText = dueText
        self.timestamp = timestamp
    }
}

/// Output schema for General Meeting / Lecture template (§11.4).
@Generable
public struct GeneralMeetingOutput: Codable, Sendable, Equatable {
    @Guide(description: "Comprehensive meeting overview capturing main thesis in 3-5 concise sentences")
    public var overview: String
    
    @Guide(description: "Bulleted list of key discussion topics and points under 20 words each")
    public var keyDiscussionPoints: [String]
    
    @Guide(description: "List of explicit decisions made and agreed upon during the meeting")
    public var decisions: [String]
    
    @Guide(description: "List of clear action items extracted from the meeting")
    public var actionItems: [RawActionItem]
    
    public init(
        overview: String = "",
        keyDiscussionPoints: [String] = [],
        decisions: [String] = [],
        actionItems: [RawActionItem] = []
    ) {
        self.overview = overview
        self.keyDiscussionPoints = keyDiscussionPoints
        self.decisions = decisions
        self.actionItems = actionItems
    }
}

/// Output schema for Client / Consulting Meeting template (§11.4).
@Generable
public struct ClientConsultingOutput: Codable, Sendable, Equatable {
    @Guide(description: "High-level executive summary tailored for client and consulting stakeholders")
    public var executiveSummary: String
    
    @Guide(description: "Stated client goals, requirements, and pain points in near-verbatim language")
    public var clientNeedsAndGoals: [String]
    
    @Guide(description: "Proposed solutions, deliverables, and scope boundaries discussed")
    public var proposedSolutionsAndScope: [String]
    
    @Guide(description: "Commercials, pricing, budget constraints, and milestone timelines")
    public var commercialsAndTimeline: String
    
    @Guide(description: "Follow-up commitments and action items assigned to either party")
    public var actionItems: [RawActionItem]
    
    public init(
        executiveSummary: String = "",
        clientNeedsAndGoals: [String] = [],
        proposedSolutionsAndScope: [String] = [],
        commercialsAndTimeline: String = "",
        actionItems: [RawActionItem] = []
    ) {
        self.executiveSummary = executiveSummary
        self.clientNeedsAndGoals = clientNeedsAndGoals
        self.proposedSolutionsAndScope = proposedSolutionsAndScope
        self.commercialsAndTimeline = commercialsAndTimeline
        self.actionItems = actionItems
    }
}

/// Output schema for Contractor Job Walk-Through template (§11.4).
@Generable
public struct ContractorWalkthroughOutput: Codable, Sendable, Equatable {
    @Guide(description: "Job site address, room identification, or physical location context")
    public var locationAndContext: String
    
    @Guide(description: "Specific scope of work and exact spoken measurements (never invented or converted)")
    public var scopeOfWork: [String]
    
    @Guide(description: "List of required materials, equipment, or supplies explicitly stated")
    public var materialsAndEquipment: [String]
    
    @Guide(description: "Job site hazards, access constraints, permit requirements, or utility shutoffs")
    public var hazardsAndConstraints: [String]
    
    @Guide(description: "Trade assignments, tasks to complete, and deadline commitments")
    public var actionItems: [RawActionItem]
    
    public init(
        locationAndContext: String = "",
        scopeOfWork: [String] = [],
        materialsAndEquipment: [String] = [],
        hazardsAndConstraints: [String] = [],
        actionItems: [RawActionItem] = []
    ) {
        self.locationAndContext = locationAndContext
        self.scopeOfWork = scopeOfWork
        self.materialsAndEquipment = materialsAndEquipment
        self.hazardsAndConstraints = hazardsAndConstraints
        self.actionItems = actionItems
    }
}

/// Intermediate schema for Map-Reduce chunking phase (§11.3).
@Generable
public struct IntermediateChunkOutput: Codable, Sendable, Equatable {
    @Guide(description: "Concise summary notes for this transcript section")
    public var summaryNotes: [String]
    
    @Guide(description: "Key facts, decisions, or measurements in this section")
    public var keyFacts: [String]
    
    @Guide(description: "Candidate action items mentioned in this section")
    public var candidateActions: [RawActionItem]
    
    public init(
        summaryNotes: [String] = [],
        keyFacts: [String] = [],
        candidateActions: [RawActionItem] = []
    ) {
        self.summaryNotes = summaryNotes
        self.keyFacts = keyFacts
        self.candidateActions = candidateActions
    }
}
