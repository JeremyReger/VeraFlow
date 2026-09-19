import SwiftData
import SwiftUI

/// Settings → Templates (v1.1 plan item 13): the three built-ins and the user's own, made from
/// a built-in base with sections switched off and a focus line. Unlocked only.
struct TemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState: AppState?
    @Query(sort: \CustomTemplate.createdAt) private var templates: [CustomTemplate]
    @State private var editing: CustomTemplate?
    @State private var isCreating = false
    @State private var showsPaywall = false

    private var isUnlocked: Bool { appState?.isUnlocked ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                VStack(alignment: .leading, spacing: 10) {
                    VFSectionLabel("Built in")
                    VFSettingsGroup {
                        ForEach(Array(TemplateID.allCases.enumerated()), id: \.element) { position, template in
                            if position > 0 { VFHairline() }
                            VFSettingsRow(title: template.displayName, detail: SummarySection.sections(for: template).map(\.displayName).joined(separator: " · ")) {
                                EmptyView()
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    VFSectionLabel("Your templates")
                    VFSettingsGroup {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { position, template in
                            if position > 0 { VFHairline() }
                            Button {
                                if ExportGate.isAllowed(.customTemplates, unlocked: isUnlocked) {
                                    editing = template
                                } else {
                                    showsPaywall = true
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(template.name).vfText(VFText.rowLabel)
                                        Text(Self.detail(for: template)).vfText(VFText.meta, color: VFColor.textTertiary).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(VFColor.textTertiary)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 54)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("templates.custom")
                        }
                        if !templates.isEmpty { VFHairline() }
                        Button {
                            if ExportGate.isAllowed(.customTemplates, unlocked: isUnlocked) {
                                isCreating = true
                            } else {
                                showsPaywall = true
                            }
                        } label: {
                            HStack {
                                Label("New template", systemImage: ExportGate.isAllowed(.customTemplates, unlocked: isUnlocked) ? "plus.circle" : "lock")
                                    .vfText(VFText.rowLabel, color: VFColor.accent)
                                Spacer()
                            }
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(ExportGate.isAllowed(.customTemplates, unlocked: isUnlocked) ? "" : "Opens the unlock screen")
                        .accessibilityIdentifier("templates.new")
                    }
                    Text("A template of your own starts from a built-in one: switch off the sections you don't need and add a line the summary should pay particular attention to. The model still uses only what was said.")
                        .vfText(VFText.snippet, color: VFColor.textTertiary)
                }
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.top, 8)
            .padding(.bottom, VFSpace.bottomInset)
        }
        .background(VFColor.background.ignoresSafeArea())
        .navigationTitle("Templates")
        .toolbarTitleDisplayMode(.inline)
        .vfNavigationBar(.visible)
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template)
        }
        .sheet(isPresented: $isCreating) {
            TemplateEditorView(template: nil)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
                .vfSheetSize(width: 520, height: 720)
        }
    }

    static func detail(for template: CustomTemplate) -> String {
        var parts = ["Based on \(template.base.shortName)"]
        let hidden = SummarySection.sections(for: template.base).filter { template.hiddenSections.contains($0) }
        if !hidden.isEmpty { parts.append("without " + hidden.map { $0.displayName.lowercased() }.joined(separator: ", ")) }
        if !template.focus.isEmpty { parts.append("focus: \(template.focus)") }
        return parts.joined(separator: " · ")
    }
}

/// Name, base, section toggles, focus, delete (v1.1 plan item 13).
struct TemplateEditorView: View {
    let template: CustomTemplate?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var base: TemplateID
    @State private var hidden: Set<SummarySection>
    @State private var focus: String
    @State private var confirmDelete = false

    init(template: CustomTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _base = State(initialValue: template?.base ?? .general)
        _hidden = State(initialValue: template?.hiddenSections ?? [])
        _focus = State(initialValue: template?.focus ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Board meeting", text: $name)
                        .accessibilityIdentifier("template.name")
                }
                Section("Based on") {
                    Picker("Based on", selection: $base) {
                        ForEach(TemplateID.allCases) { template in
                            Text(template.displayName).tag(template)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    ForEach(SummarySection.sections(for: base)) { section in
                        Toggle(section.displayName, isOn: Binding(
                            get: { !hidden.contains(section) },
                            set: { on in if on { hidden.remove(section) } else { hidden.insert(section) } }
                        ))
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    Text("Switched-off sections are hidden in the app and left out of exports. They are still made, so switching one back on costs nothing.")
                }
                Section {
                    TextField("e.g. the budget and who owns each risk", text: $focus, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("template.focus")
                } header: {
                    Text("Focus (optional)")
                } footer: {
                    Text("One line the summary pays particular attention to. Up to \(FocusLine.maximumLength) characters; it can't change the rules the model follows.")
                }
                if template != nil {
                    Section {
                        Button("Delete template", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("template.delete")
                    } footer: {
                        Text("Recordings made with it keep their summaries and fall back to the built-in template.")
                    }
                    .confirmationDialog("Delete this template?", isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            if let template { modelContext.delete(template) }
                            try? modelContext.save()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle(template == nil ? "New template" : "Edit template")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("template.save")
                }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = Set(SummarySection.sections(for: base))
        if let template {
            template.name = cleanName
            template.base = base
            template.hiddenSections = hidden.intersection(allowed)
            template.focus = FocusLine.sanitize(focus)
        } else {
            modelContext.insert(CustomTemplate(name: cleanName, base: base, hiddenSections: Array(hidden.intersection(allowed)), focus: focus))
        }
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        TemplatesView()
    }
    .modelContainer(PreviewData.container())
    .environment(AppState(services: .fakes()))
}
