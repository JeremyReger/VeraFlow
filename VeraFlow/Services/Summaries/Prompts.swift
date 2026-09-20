import Foundation

/// Versioned model instructions (SPEC §11.5). `version` is saved in `SummaryRecord.modelInfo`
/// so a summary can be traced to the prompt that produced it.
enum Prompts {
    /// v5 (2026-09-20): a walk-through of a 35-second recording came back with ten rooms and
    /// twenty measurements, none of them spoken. Three things changed together, and a summary made
    /// before any of them is worth re-running: the schema descriptions no longer carry example
    /// values for the model to copy, a short transcript is answered with a smaller schema
    /// (`SummaryScale`), and `TranscriptGrounding` drops anything the transcript doesn't support.
    /// Only the last of those is a guarantee; the rules below are still only a request.
    ///
    /// v4 (2026-09-19): short is allowed. A thin transcript had the model padding every list
    /// with the same sentences, so the rules now say plainly that a short or empty list is the
    /// right answer when there is nothing more to say.
    static let version = 5

    /// Prepended to every template.
    static let sharedRules = """
    You summarize transcripts of real conversations.
    Use only information in the transcript. Never invent names, numbers, dates, prices, or measurements.
    If something is not stated, leave that field empty. An empty answer is correct when the transcript says nothing; a filled-in one that nobody said is not.
    Never repeat a value from these instructions or from the output format as if it were something that was said.
    Write plainly and concisely. No filler.
    A short list is a good answer. Say each thing once, in the one place it belongs, and stop; never repeat a line to make a list longer, and leave a list empty rather than filling it.
    Lines look like: [mm:ss] Speaker N: text. Use those timestamps when citing.
    Refer to people exactly as they are labeled or named in the transcript.
    A line like [mm:ss] ★ Marked: label is a moment the person recording flagged as important. Give what was said around it extra weight and cite its time; the label, if any, says why it mattered.
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
            return combine + " Group the key points by subject: one topic per distinct subject, in the order it came up, with the points that belong to it and the timestamp of the first line about it. A recording that covers one subject gets one topic; a short recording gets one or two. Key points are statements about what was said, never questions — a question belongs in openQuestions and nowhere else. No point may appear under more than one subject. The overview should let someone who missed the meeting understand what it was for, what was covered, what was decided, and what is still open."
        case .client:
            return combine + " This was a meeting between a consultant and a client. Focus on client goals, concerns, commitments made by either side, and next steps. List the subjects discussed in order, each with the timestamp of the first line about it."
        case .walkthrough:
            return combine + " This was a contractor walking a job site with a customer. Organize work by area/room, each with the timestamp of the first line in that area. Copy measurements exactly as spoken. List only rooms the transcript says they went into and only measurements the transcript says out loud; a walk that covered one room gets one area, and no measurements at all is the right answer when none were read out."
        }
    }

    /// When the whole transcript fits in one call, the FINAL step reads the transcript directly.
    static func finalFromTranscript(for template: TemplateID) -> String {
        final(for: template).replacingOccurrences(of: "Combine these notes into", with: "Write")
    }

    /// "Ask this recording" (v1.1 plan item 11): grounded answers over retrieved excerpts.
    static let ask = """
    Answer the question using only the transcript excerpts given. Cite the [mm:ss] time of every excerpt line the answer relies on. If the excerpts do not answer the question, set foundInTranscript to false and leave the answer empty; never guess. Never compute or convert dates, numbers, prices or measurements; repeat them exactly as spoken.
    """

    static let followUpEmail = """
    Draft a short, professional follow-up email from the consultant to the client based on this meeting summary. Thank them, restate the goals and decisions, list the action items with owners, and propose the next step. Do not add anything the summary does not say.
    """

    /// Instructions for one call: the shared rules plus the step's own text, and for the FINAL
    /// step the user's focus line last (v1.1 plan item 13).
    static func instructions(_ step: String, focus: String = "") -> String {
        var text = sharedRules + "\n\n" + step
        if let line = FocusLine.instruction(for: focus) {
            text += "\n\n" + line
        }
        return text
    }
}
