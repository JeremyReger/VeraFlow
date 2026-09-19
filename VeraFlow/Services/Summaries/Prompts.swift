import Foundation

/// Versioned model instructions (SPEC §11.5). `version` is saved in `SummaryRecord.modelInfo`
/// so a summary can be traced to the prompt that produced it.
enum Prompts {
    static let version = 2

    /// Prepended to every template.
    static let sharedRules = """
    You summarize transcripts of real conversations.
    Use only information in the transcript. Never invent names, numbers, dates, prices, or measurements.
    If something is not stated, leave that field empty.
    Write plainly and concisely. No filler.
    Lines look like: [mm:ss] Speaker N: text. Use those timestamps when citing.
    Refer to people exactly as they are labeled or named in the transcript.
    """

    /// MAP step over one chunk of a long transcript.
    static let map = """
    Extract notes from this PART of a longer transcript. Other parts are handled separately; do not guess what happens outside this part.
    """

    /// FINAL step: notes (or a short transcript) → template output.
    static func final(for template: TemplateID) -> String {
        let combine = "Combine these notes into one summary of the whole recording. Merge duplicates. Keep the most specific version of each action item."
        switch template {
        case .general:
            return combine + " Group the key points by subject: one topic per distinct subject, in the order it came up, with the points that belong to it. The overview should let someone who missed the meeting understand what it was for, what was covered, what was decided, and what is still open."
        case .client:
            return combine + " This was a meeting between a consultant and a client. Focus on client goals, concerns, commitments made by either side, and next steps."
        case .walkthrough:
            return combine + " This was a contractor walking a job site with a customer. Organize work by area/room. Copy measurements exactly as spoken."
        }
    }

    /// When the whole transcript fits in one call, the FINAL step reads the transcript directly.
    static func finalFromTranscript(for template: TemplateID) -> String {
        final(for: template).replacingOccurrences(of: "Combine these notes into", with: "Write")
    }

    static let followUpEmail = """
    Draft a short, professional follow-up email from the consultant to the client based on this meeting summary. Thank them, restate the goals and decisions, list the action items with owners, and propose the next step. Do not add anything the summary does not say.
    """

    /// Instructions for one call: the shared rules plus the step's own text.
    static func instructions(_ step: String) -> String {
        sharedRules + "\n\n" + step
    }
}
