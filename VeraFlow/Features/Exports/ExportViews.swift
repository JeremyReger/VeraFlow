import MessageUI
import SwiftData
import SwiftUI
import UIKit

/// The Share menu on the detail screen (SPEC §4.5): files, copy, email, Reminders.
struct ExportMenuItems: View {
    let recording: Recording
    let controller: ExportController
    let onSendToReminders: () -> Void
    /// Called instead of the action when the free tier doesn't include it (SPEC §13.2).
    let onLocked: () -> Void
    /// Passed in explicitly: toolbar menu content doesn't reliably see `@Environment` objects.
    let isUnlocked: Bool
    @Environment(\.services) private var services
    @AppStorage("export.includeTranscript") private var includeTranscript = true

    /// Runs `action` if the tier allows it, otherwise opens the paywall.
    private func gated(_ action: ExportGate.Action, _ run: @escaping () -> Void) -> () -> Void {
        { ExportGate.isAllowed(action, unlocked: isUnlocked) ? run() : onLocked() }
    }

    private func lockIcon(_ action: ExportGate.Action, _ systemImage: String) -> String {
        ExportGate.isAllowed(action, unlocked: isUnlocked) ? systemImage : "lock"
    }

    /// The lock icon isn't spoken; the hint says what a gated item does (A-18).
    private func lockHint(_ action: ExportGate.Action) -> String {
        ExportGate.isAllowed(action, unlocked: isUnlocked) ? "" : "Opens the unlock screen"
    }

    private var hasSummary: Bool { recording.currentSummary != nil }
    private var hasTranscript: Bool { !recording.segments.isEmpty }

    var body: some View {
        Section {
            ForEach([ExportKind.markdown, .pdf, .plainText]) { kind in
                Button(kind.title, systemImage: lockIcon(.file(kind), kind.systemImage), action: gated(.file(kind)) {
                    Task { await controller.share(kind, document: document(), audioURL: audioURL) }
                })
                .disabled(!hasSummary && !hasTranscript)
                .accessibilityHint(lockHint(.file(kind)))
            }
            Toggle("Include transcript", systemImage: "text.alignleft", isOn: $includeTranscript)
                .disabled(!hasTranscript)
        }
        Section {
            Button("Copy summary", systemImage: "doc.on.doc") {
                controller.copySummary(document())
            }
            .disabled(!hasSummary)
            Button("Copy action items", systemImage: "checklist") {
                controller.copyActionItems(document())
            }
            .disabled(actionItems.isEmpty)
        }
        Section {
            Button(recording.currentSummary?.templateID == .client ? "Draft follow-up email" : "Email summary", systemImage: lockIcon(.email, "envelope"), action: gated(.email) {
                Task { await controller.draftEmail(for: document()) }
            })
            .disabled(!hasSummary)
            .accessibilityHint(lockHint(.email))
            Button("Send action items to Reminders", systemImage: lockIcon(.reminders, "list.bullet.rectangle"), action: gated(.reminders) {
                onSendToReminders()
            })
            .disabled(actionItems.isEmpty)
            .accessibilityHint(lockHint(.reminders))
        }
        Section {
            Button(ExportKind.audio.title, systemImage: lockIcon(.file(.audio), ExportKind.audio.systemImage), action: gated(.file(.audio)) {
                Task { await controller.share(.audio, document: document(), audioURL: audioURL) }
            })
            .accessibilityHint(lockHint(.file(.audio)))
        }
    }

    private var actionItems: [ActionItem] {
        (try? recording.currentSummary?.resolvedPayload())?.actionItems ?? []
    }

    private var audioURL: URL {
        services.storage.audioURL(for: recording.id, fileName: recording.audioFileName)
    }

    private func document() -> ExportDocument {
        ExportDocument.make(from: recording, includeTranscript: includeTranscript)
    }
}

/// Presents the share sheet, the mail composer, and the export error alert.
struct ExportPresentation: ViewModifier {
    @Bindable var controller: ExportController

    func body(content: Content) -> some View {
        content
            .sheet(item: $controller.shareItem, onDismiss: { controller.finishSharing() }) { item in
                ActivityView(items: [item.url])
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $controller.mailDraft) { draft in
                if MFMailComposeViewController.canSendMail() {
                    MailComposeView(subject: draft.subject, body: draft.body)
                        .ignoresSafeArea()
                } else {
                    // No Mail account: hand the text to the share sheet (SPEC §12 fallback).
                    ActivityView(items: [draft.subject + "\n\n" + draft.body])
                        .presentationDetents([.medium, .large])
                }
            }
            .alert("Export problem", isPresented: Binding(
                get: { controller.errorMessage != nil },
                set: { if !$0 { controller.errorMessage = nil } }
            )) {
                Button("OK") { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
    }
}

/// `UIActivityViewController` for files or text.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// `MFMailComposeViewController` prefilled with a draft.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    // Main-actor bound like the delegate protocol, so it can call the SwiftUI dismiss action.
    @MainActor
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        // The delegate protocol is nonisolated; hop back to the main actor to dismiss.
        nonisolated func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            Task { @MainActor in self.dismiss() }
        }
    }
}

/// Pick a Reminders list and the action items to send (SPEC §12). Items already sent are shown
/// checked and disabled so nothing is duplicated.
struct RemindersSheet: View {
    let recording: Recording
    let record: SummaryRecord
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var lists: [ReminderList] = []
    @State private var selectedListID: String?
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var alreadySent: [UUID: String] = [:]
    @State private var items: [ActionItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(VFColor.danger)
                    }
                }
                Section("List") {
                    if isLoading {
                        ProgressView("Loading lists…")
                    } else if lists.isEmpty {
                        Text("No Reminders lists found.").foregroundStyle(.secondary)
                    } else {
                        Picker("List", selection: $selectedListID) {
                            ForEach(lists) { list in
                                Text(list.title).tag(Optional(list.id))
                            }
                        }
                    }
                }
                Section {
                    ForEach(items) { item in
                        let sent = alreadySent[item.id] != nil
                        Button {
                            if selectedItemIDs.contains(item.id) {
                                selectedItemIDs.remove(item.id)
                            } else {
                                selectedItemIDs.insert(item.id)
                            }
                        } label: {
                            HStack(alignment: .top) {
                                Image(systemName: sent || selectedItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(sent ? Color.secondary : Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                    if let due = item.dueDate {
                                        Text("Due " + due.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if sent {
                                        Text("Already in Reminders").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(sent)
                        // Selection is otherwise only a glyph (A-8).
                        .accessibilityAddTraits(selectedItemIDs.contains(item.id) ? .isSelected : [])
                        .accessibilityValue(sent ? "Already in Reminders" : selectedItemIDs.contains(item.id) ? "Selected" : "Not selected")
                    }
                } header: {
                    Text("Action items")
                } footer: {
                    Text("Each reminder gets the task as its title, the owner and recording as notes, and the due date when one was said.")
                }
            }
            .navigationTitle("Send to Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "Sending…" : "Send") {
                        Task { await send() }
                    }
                    .disabled(isSending || selectedListID == nil || selectedItemIDs.isEmpty)
                    .accessibilityIdentifier("reminders.send")
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        items = (try? record.resolvedPayload())?.actionItems ?? []
        alreadySent = (try? record.actionItems())?.reminderIDs ?? [:]
        selectedItemIDs = Set(items.map(\.id)).subtracting(alreadySent.keys)
        do {
            lists = try await services.exporter.reminderLists()
            selectedListID = lists.first?.id
        } catch {
            errorMessage = ExportController.message(for: error)
        }
        isLoading = false
    }

    private func send() async {
        guard let list = lists.first(where: { $0.id == selectedListID }) else { return }
        isSending = true
        defer { isSending = false }
        let requests = items.filter { selectedItemIDs.contains($0.id) }.map { item in
            ReminderRequest(
                actionItem: item,
                recordingTitle: recording.title,
                ownerDisplayName: item.ownerSpeakerKey.flatMap { key in recording.speakers.first { $0.key == key }?.displayName } ?? item.owner
            )
        }
        do {
            let created = try await services.exporter.createReminders(requests, in: list)
            var state = (try? record.actionItems()) ?? ActionItemsState()
            state.reminderIDs.merge(created) { _, new in new }
            record.actionItemsState = (try? JSONEncoder().encode(state)) ?? record.actionItemsState
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = ExportController.message(for: error)
        }
    }
}
