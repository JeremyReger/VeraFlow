import Foundation

/// Which parts of a summary are prose and get translated (v1.1 plan item 14). Names, due-date
/// phrases, dates, timestamps, measurements and quantities are structured or verbatim and stay
/// exactly as the model gave them.
enum SummaryTranslation {
    /// Every translatable string in a fixed order.
    static func strings(of payload: SummaryPayload) -> [String] {
        var collected: [String] = []
        var copy = payload
        visit(&copy) { collected.append($0) }
        return collected
    }

    /// The payload with its prose replaced by `translated`, in the order `strings(of:)` gives.
    /// A short list leaves the rest untouched; a long one is truncated.
    static func applying(_ translated: [String], to payload: SummaryPayload) -> SummaryPayload {
        var copy = payload
        var iterator = translated.makeIterator()
        visit(&copy) { text in
            if let next = iterator.next() { text = next }
        }
        return copy
    }

    /// Walks the prose fields of every template in one place, so collecting and applying can't
    /// disagree about the order.
    private static func visit(_ payload: inout SummaryPayload, _ body: (inout String) -> Void) {
        switch payload {
        case .general(var summary):
            body(&summary.title)
            body(&summary.overview)
            each(&summary.keyPoints, body)
            for index in summary.topics.indices {
                body(&summary.topics[index].title)
                each(&summary.topics[index].points, body)
            }
            each(&summary.decisions, body)
            actionItems(&summary.actionItems, body)
            each(&summary.openQuestions, body)
            payload = .general(summary)
        case .client(var summary):
            body(&summary.title)
            body(&summary.overview)
            each(&summary.clientGoals, body)
            each(&summary.concerns, body)
            each(&summary.decisions, body)
            actionItems(&summary.actionItems, body)
            body(&summary.nextMeeting)
            each(&summary.openQuestions, body)
            for index in summary.topics.indices {
                body(&summary.topics[index].title)
                each(&summary.topics[index].points, body)
            }
            payload = .client(summary)
        case .walkthrough(var summary):
            body(&summary.title)
            // `location` is an address: verbatim.
            body(&summary.overview)
            for index in summary.areas.indices {
                body(&summary.areas[index].name)
                each(&summary.areas[index].tasks, body)
                for measurement in summary.areas[index].measurements.indices {
                    // The item is prose ("Kitchen wall, north"); the value is verbatim.
                    body(&summary.areas[index].measurements[measurement].item)
                }
                for material in summary.areas[index].materials.indices {
                    body(&summary.areas[index].materials[material].name)
                    body(&summary.areas[index].materials[material].notes)
                }
            }
            each(&summary.customerRequests, body)
            each(&summary.issuesFound, body)
            each(&summary.quoteNotes, body)
            actionItems(&summary.actionItems, body)
            payload = .walkthrough(summary)
        }
    }

    private static func each(_ strings: inout [String], _ body: (inout String) -> Void) {
        for index in strings.indices { body(&strings[index]) }
    }

    /// Only the task; owner and due phrase are kept as spoken so they still match speakers and
    /// the date resolver's input.
    private static func actionItems(_ items: inout [ActionItem], _ body: (inout String) -> Void) {
        for index in items.indices { body(&items[index].task) }
    }
}

/// Stored in `SummaryRecord.translationsJSON`: one translated payload per target language,
/// keyed by BCP-47 identifier.
typealias SummaryTranslations = [String: SummaryPayload]
