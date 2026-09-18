import SwiftUI

/// Add and remove tags on one recording; suggests tags already used elsewhere.
struct TagEditorView: View {
    @State private var tags: [String]
    @State private var draft = ""
    let suggestions: [String]
    let onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss

    init(tags: [String], suggestions: [String], onSave: @escaping ([String]) -> Void) {
        _tags = State(initialValue: tags)
        self.suggestions = suggestions
        self.onSave = onSave
    }

    private var unusedSuggestions: [String] {
        let current = Set(tags.map { $0.lowercased() })
        return suggestions.filter { !current.contains($0.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Add a tag") {
                    HStack {
                        TextField("Tag", text: $draft)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addDraft)
                            .accessibilityIdentifier("tags.field")
                        Button("Add", action: addDraft)
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                        }
                        .onDelete { offsets in
                            tags.remove(atOffsets: offsets)
                        }
                    }
                }
                if !unusedSuggestions.isEmpty {
                    Section("Used elsewhere") {
                        ForEach(unusedSuggestions, id: \.self) { tag in
                            Button {
                                tags = LibraryActions.normalized(tags + [tag])
                            } label: {
                                Label(tag, systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Swipe-to-delete has a visible alternative for Switch Control and keyboards (A-27).
                if !tags.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(LibraryActions.normalized(tags))
                        dismiss()
                    }
                    .accessibilityIdentifier("tags.done")
                }
            }
        }
    }

    private func addDraft() {
        tags = LibraryActions.normalized(tags + [draft])
        draft = ""
    }
}

#Preview {
    TagEditorView(tags: ["contractor"], suggestions: ["client", "lecture"]) { _ in }
}
