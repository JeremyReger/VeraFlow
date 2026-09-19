import SwiftUI

/// Edit or add one action item (v1.1 plan item 2): task, owner, due date, delete. Edits are
/// stored next to the summary, never in the model's output.
struct ActionItemEditor: View {
    let speakers: [Speaker]
    let isNew: Bool
    let onSave: (ActionItem) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var item: ActionItem
    @State private var ownerChoice: OwnerChoice
    @State private var ownerText: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var confirmDelete = false

    private enum OwnerChoice: Hashable {
        case nobody
        case speaker(String)
        case other
    }

    init(item: ActionItem, speakers: [Speaker], isNew: Bool, onSave: @escaping (ActionItem) -> Void, onDelete: (() -> Void)? = nil) {
        self.speakers = speakers.sorted { $0.key < $1.key }
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _item = State(initialValue: item)
        if let key = item.ownerSpeakerKey, speakers.contains(where: { $0.key == key }) {
            _ownerChoice = State(initialValue: .speaker(key))
            _ownerText = State(initialValue: "")
        } else if item.owner.isEmpty {
            _ownerChoice = State(initialValue: .nobody)
            _ownerText = State(initialValue: "")
        } else {
            _ownerChoice = State(initialValue: .other)
            _ownerText = State(initialValue: item.owner)
        }
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing", text: $item.task, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("actionItem.task")
                }
                Section("Owner") {
                    Picker("Owner", selection: $ownerChoice) {
                        Text("No one").tag(OwnerChoice.nobody)
                        ForEach(speakers, id: \.key) { speaker in
                            Text(speaker.displayName).tag(OwnerChoice.speaker(speaker.key))
                        }
                        Text("Someone else").tag(OwnerChoice.other)
                    }
                    if ownerChoice == .other {
                        TextField("Name", text: $ownerText)
                            .accessibilityIdentifier("actionItem.ownerName")
                    }
                }
                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate)
                            .accessibilityIdentifier("actionItem.dueDate")
                    }
                } footer: {
                    if !item.dueText.isEmpty {
                        Text("Said as: \u{201C}\(item.dueText)\u{201D}")
                    }
                }
                if let onDelete {
                    Section {
                        Button("Delete action item", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("actionItem.delete")
                    } footer: {
                        if !isNew {
                            Text("A reminder already sent for this item isn't changed.")
                        }
                    }
                    .confirmationDialog("Delete this action item?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle(isNew ? "New action item" : "Edit action item")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(resolved)
                        dismiss()
                    }
                    .disabled(item.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("actionItem.save")
                }
            }
        }
    }

    /// The item as edited: trimmed task, owner from the picker, due date only when switched on.
    private var resolved: ActionItem {
        var result = item
        result.task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
        switch ownerChoice {
        case .nobody:
            result.owner = ""
            result.ownerSpeakerKey = nil
        case .speaker(let key):
            result.owner = speakers.first { $0.key == key }?.displayName ?? ""
            result.ownerSpeakerKey = key
        case .other:
            result.owner = ownerText.trimmingCharacters(in: .whitespacesAndNewlines)
            result.ownerSpeakerKey = nil
        }
        result.dueDate = hasDueDate ? dueDate : nil
        return result
    }
}
