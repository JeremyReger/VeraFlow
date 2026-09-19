import SwiftUI

/// Edits one block of a summary (v1.1 plan item 18): rewrite a line, delete one, add one, or
/// put the model's own words back. Like the action-item editor, nothing here touches the stored
/// payload — the result is handed back as a `SummaryEdits` change.
struct SummarySectionEditor: View {
    let field: SummaryField
    /// What the model wrote, before any edit. "Use the original" restores this.
    let modelLines: [String]
    let modelParagraph: String
    let hasEdits: Bool
    let onSave: (SummarySectionEdit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [Line]
    @State private var paragraph: String
    @FocusState private var focused: UUID?

    /// A line with a stable id, so SwiftUI keeps the text fields in place while one is deleted.
    private struct Line: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    init(
        field: SummaryField,
        modelLines: [String] = [],
        modelParagraph: String = "",
        currentLines: [String] = [],
        currentParagraph: String = "",
        hasEdits: Bool,
        onSave: @escaping (SummarySectionEdit) -> Void
    ) {
        self.field = field
        self.modelLines = modelLines
        self.modelParagraph = modelParagraph
        self.hasEdits = hasEdits
        self.onSave = onSave
        _lines = State(initialValue: currentLines.map { Line(text: $0) })
        _paragraph = State(initialValue: currentParagraph)
    }

    var body: some View {
        NavigationStack {
            Form {
                if field.isParagraph {
                    paragraphSection
                } else {
                    linesSection
                }
                if hasEdits {
                    Section {
                        Button("Use the original wording", systemImage: "arrow.uturn.backward") {
                            restoreOriginal()
                        }
                        .accessibilityIdentifier("summarySection.revert")
                    } footer: {
                        Text("Puts back what the model wrote for this section.")
                    }
                }
            }
            .navigationTitle(field.title)
            .toolbarTitleDisplayMode(.inline)
            .vfSheetSize(width: 520, height: 560)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(result)
                        dismiss()
                    }
                    .accessibilityIdentifier("summarySection.save")
                }
            }
        }
    }

    @ViewBuilder
    private var paragraphSection: some View {
        Section {
            TextField(field.title, text: $paragraph, axis: .vertical)
                .lineLimit(3...12)
                .accessibilityIdentifier("summarySection.paragraph")
        } footer: {
            Text("Your wording. The recording, the transcript, and the model's version are unchanged.")
        }
    }

    @ViewBuilder
    private var linesSection: some View {
        Section {
            ForEach($lines) { $line in
                TextField(field.lineNoun.capitalized, text: $line.text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused, equals: line.id)
                    .frame(minHeight: VFMetric.minHit)
            }
            .onDelete { lines.remove(atOffsets: $0) }
            Button {
                let line = Line(text: "")
                lines.append(line)
                focused = line.id
            } label: {
                Label("Add \(field.lineNounWithArticle)", systemImage: "plus.circle")
                    .vfText(VFText.rowLabel, color: VFColor.accent)
                    .frame(minHeight: VFMetric.minHit)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("summarySection.add")
        } footer: {
            Text("Swipe a line to delete it. An empty line is dropped when you save.")
        }
    }

    private func restoreOriginal() {
        if field.isParagraph {
            paragraph = modelParagraph
        } else {
            lines = modelLines.map { Line(text: $0) }
        }
    }

    private var result: SummarySectionEdit {
        if field.isParagraph {
            return .paragraph(paragraph)
        }
        return .lines(lines.map(\.text))
    }
}

/// What the editor produced for one field.
enum SummarySectionEdit: Equatable, Sendable {
    case lines([String])
    case paragraph(String)
}

extension SummaryEdits {
    /// Folds the editor's result into the overlay. `model` is what the summary itself holds.
    mutating func apply(_ edit: SummarySectionEdit, in field: SummaryField, model: SummaryPayload) {
        switch edit {
        case .lines(let lines):
            replace(lines, model: model.list(for: field) ?? [], in: field)
        case .paragraph(let text):
            setParagraph(text, model: model.paragraph(for: field) ?? "", in: field)
        }
    }
}
