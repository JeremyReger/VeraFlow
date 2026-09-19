import Foundation

/// Removes content the model repeated instead of summarizing (Jeremy, 2026-09-19).
///
/// A short recording can't fill a schema that asks for up to 8 topics of 5 points each, and a
/// small on-device model pads by copying what it has already written. On the 1:58 "Coaching Staff"
/// recording three topics came back with byte-identical point lists, and those "points" were the
/// open questions repeated verbatim. `.maximumCount` stopped the padding running past the context
/// window; it could never stop the padding itself, so the duplicates are dropped here, where the
/// rule is ours and doesn't depend on the model behaving.
///
/// Every rule keeps the FIRST occurrence and the original order. Nothing is rewritten, merged or
/// invented: text either survives untouched or is dropped.
///
/// Action items are deliberately absent: `ActionItemPostProcessor.process` already merges them on
/// token similarity and owner, which is a better rule than string identity and keeps the fields
/// each copy filled in.
enum SummaryDeduplicator {
    /// Case-, accent- and punctuation-insensitive identity. Two lines that differ only in a
    /// trailing period, an apostrophe or run of spaces read as the same sentence, so they count
    /// as the same line here.
    static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let scalars = folded.unicodeScalars.compactMap { scalar -> Character? in
            // Apostrophes vanish rather than split, so "coach's" and "coachs" are one word.
            if apostrophes.contains(scalar) { return nil }
            return CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}", "\u{02BC}"]

    /// Later repeats of the same line, and blank lines, gone.
    static func unique(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        return items.filter { item in
            let itemKey = key(item)
            guard !itemKey.isEmpty else { return false }
            return seen.insert(itemKey).inserted
        }
    }

    /// Drops a point already used under an earlier topic, then any topic left with nothing to
    /// show. A point phrased as a question that is also listed as an open question is not a key
    /// point — that is how the same three sentences reached all three topics on the 1:58
    /// recording — so it goes too.
    static func topics(_ topics: [KeyPointTopic], questions: [String] = []) -> [KeyPointTopic] {
        let questionKeys = Set(questions.map(key))
        var seenPoints: Set<String> = []
        var seenTitles: Set<String> = []
        var result: [KeyPointTopic] = []
        for topic in topics {
            let titleKey = key(topic.title)
            // A repeated heading is the same padding one level up.
            if !titleKey.isEmpty, !seenTitles.insert(titleKey).inserted { continue }
            let points = topic.points.filter { point in
                let pointKey = key(point)
                guard !pointKey.isEmpty else { return false }
                let isRepeatedQuestion = point.trimmingCharacters(in: .whitespaces).hasSuffix("?")
                    && questionKeys.contains(pointKey)
                guard !isRepeatedQuestion else { return false }
                return seenPoints.insert(pointKey).inserted
            }
            guard !points.isEmpty else { continue }
            result.append(KeyPointTopic(title: topic.title, points: points, start: topic.start))
        }
        return result
    }

    /// The walk-through's version of `topics(_:questions:)`: tasks are deduplicated across areas,
    /// measurements by what was measured and the value read out, materials by name.
    ///
    /// Unlike a topic, an area is kept even when nothing is left under it. A topic with no points
    /// is already dropped at display time by `KeyPointLayout.groups`, so dropping it here changes
    /// nothing; an area is also a chapter, and "at 1:30 they were in the bathroom" is worth
    /// keeping even when nothing was said there. Only a repeated area NAME removes one.
    static func areas(_ areas: [WorkArea]) -> [WorkArea] {
        var seenTasks: Set<String> = []
        var seenMeasurements: Set<String> = []
        var seenMaterials: Set<String> = []
        var seenNames: Set<String> = []
        var result: [WorkArea] = []
        for area in areas {
            let nameKey = key(area.name)
            if !nameKey.isEmpty, !seenNames.insert(nameKey).inserted { continue }
            let tasks = area.tasks.filter { task in
                let taskKey = key(task)
                return !taskKey.isEmpty && seenTasks.insert(taskKey).inserted
            }
            let measurements = area.measurements.filter { measurement in
                let measurementKey = key(measurement.item + " " + measurement.value)
                return !measurementKey.isEmpty && seenMeasurements.insert(measurementKey).inserted
            }
            let materials = area.materials.filter { material in
                let materialKey = key(material.name)
                return !materialKey.isEmpty && seenMaterials.insert(materialKey).inserted
            }
            result.append(WorkArea(
                name: area.name,
                tasks: tasks,
                measurements: measurements,
                materials: materials,
                start: area.start
            ))
        }
        return result
    }

    /// Runs every rule over a whole payload. Called before chapter starts are worked out, so a
    /// dropped topic never claims a chapter.
    static func cleaned(_ payload: SummaryPayload) -> SummaryPayload {
        switch payload {
        case .general(var summary):
            summary.openQuestions = unique(summary.openQuestions)
            // `keyPoints` is the flat copy exports and search read; keep it saying what the
            // topics now say. The fallback is only for an older summary that never had topics —
            // asking whether any SURVIVED would put every dropped point back, since `keyPoints`
            // is the flat copy of the topics that were just cleaned.
            let hadTopics = !summary.topics.isEmpty
            summary.topics = topics(summary.topics, questions: summary.openQuestions)
            summary.keyPoints = hadTopics ? summary.topics.flatMap(\.points) : unique(summary.keyPoints)
            summary.decisions = unique(summary.decisions)
            return .general(summary)
        case .client(var summary):
            summary.openQuestions = unique(summary.openQuestions)
            summary.topics = topics(summary.topics, questions: summary.openQuestions)
            summary.clientGoals = unique(summary.clientGoals)
            summary.concerns = unique(summary.concerns)
            summary.decisions = unique(summary.decisions)
            return .client(summary)
        case .walkthrough(var summary):
            summary.areas = areas(summary.areas)
            summary.customerRequests = unique(summary.customerRequests)
            summary.issuesFound = unique(summary.issuesFound)
            summary.quoteNotes = unique(summary.quoteNotes)
            return .walkthrough(summary)
        }
    }
}
