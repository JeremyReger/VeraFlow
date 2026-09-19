import SwiftData
import SwiftUI

/// Settings → Storage: what the recordings take up, and a way to drop audio files while
/// keeping every transcript, speaker label, summary and mark (Jeremy, 2026-09-19).
struct StorageView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var items: [StorageItem] = []
    @State private var filter = StorageFilter()
    @State private var selected: Set<UUID> = []
    @State private var confirmRemove = false
    @State private var isWorking = false
    @State private var message: String?

    private var shown: [StorageItem] { filter.apply(to: items) }
    private var selectedItems: [StorageItem] { shown.filter { selected.contains($0.id) } }
    private var selectedBytes: Int64 { StorageMath.totalBytes(selectedItems) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                    totals
                    controls
                    rows
                }
                .padding(.horizontal, VFSpace.gutter)
                .padding(.top, VFSpace.sectionGap)
                .padding(.bottom, VFSpace.bottomInset)
            }
            if !items.isEmpty {
                actionBar
            }
        }
        .background(VFColor.background.ignoresSafeArea())
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(VFColor.background, for: .navigationBar)
        .confirmationDialog(
            "Remove audio from ^[\(selected.count) recording](inflect: true)?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove Audio", role: .destructive) {
                Task { await removeSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Frees \(StorageMath.text(bytes: selectedBytes)). Transcripts, speaker labels, summaries and marks stay. The audio can't be recovered.")
        }
        .alert("Storage", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .task(id: recordings.count) { reload() }
    }

    // MARK: Totals

    private var totals: some View {
        VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("On this iPhone")
            VFSettingsGroup {
                VFSettingsRow(title: "Audio files") {
                    Text(StorageMath.text(bytes: StorageMath.totalBytes(items)))
                        .vfText(VFText.meta, color: VFColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                VFHairline()
                VFSettingsRow(title: "Recordings with audio") {
                    Text("\(items.count) of \(recordings.count)")
                        .vfText(VFText.meta, color: VFColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
                if let free = services.storage.availableCapacity() {
                    VFHairline()
                    VFSettingsRow(title: "Free space") {
                        Text(StorageMath.text(bytes: free))
                            .vfText(VFText.meta, color: VFColor.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            VFReassurance("Removing audio keeps everything written from it: the transcript, speaker labels, summary and marks.")
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VFSectionLabel("Recordings")
                Spacer()
                Menu {
                    ForEach(StorageSort.allCases) { sort in
                        Button {
                            filter.sort = sort
                        } label: {
                            if sort == filter.sort {
                                Label(sort.displayName, systemImage: "checkmark")
                            } else {
                                Text(sort.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(filter.sort.displayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .vfText(VFText.meta, color: VFColor.textSecondary)
                    .frame(minHeight: VFMetric.minHit)
                }
                .accessibilityLabel("Sort: \(filter.sort.displayName)")
                .accessibilityIdentifier("storage.sort")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    VFChip("All", isSelected: filter.olderThanDays == nil) {
                        filter.olderThanDays = nil
                    }
                    ForEach(StorageFilter.ageChoices, id: \.self) { days in
                        VFChip("Older than \(days) days", isSelected: filter.olderThanDays == days) {
                            filter.olderThanDays = days
                        }
                    }
                    VFChip("Has summary", isSelected: filter.onlyWithSummary) {
                        filter.onlyWithSummary.toggle()
                    }
                }
            }
            .accessibilityIdentifier("storage.filters")
            HStack {
                Button(allShownSelected ? "Deselect all" : "Select all shown") {
                    if allShownSelected {
                        selected.subtract(shown.map(\.id))
                    } else {
                        selected.formUnion(shown.filter(\.canRemoveAudio).map(\.id))
                    }
                }
                .vfText(VFText.rowLabel, color: VFColor.accent)
                .frame(minHeight: VFMetric.minHit)
                .disabled(shown.allSatisfy { !$0.canRemoveAudio })
                .accessibilityIdentifier("storage.selectAll")
                Spacer()
                Text("\(shown.count) shown · \(StorageMath.text(bytes: StorageMath.totalBytes(shown)))")
                    .vfText(VFText.meta, color: VFColor.textTertiary)
            }
        }
    }

    private var allShownSelected: Bool {
        let eligible = shown.filter(\.canRemoveAudio).map(\.id)
        return !eligible.isEmpty && eligible.allSatisfy { selected.contains($0) }
    }

    // MARK: Rows

    @ViewBuilder
    private var rows: some View {
        if items.isEmpty {
            Text(recordings.isEmpty ? "No recordings yet." : "Every recording's audio has already been removed.")
                .vfText(VFText.body, color: VFColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else if shown.isEmpty {
            Text("Nothing matches these filters.")
                .vfText(VFText.body, color: VFColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            VFSettingsGroup {
                ForEach(Array(shown.enumerated()), id: \.element.id) { position, item in
                    if position > 0 { VFHairline() }
                    row(item)
                }
            }
        }
    }

    private func row(_ item: StorageItem) -> some View {
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected { selected.remove(item.id) } else { selected.insert(item.id) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? VFColor.accent : VFColor.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .vfText(VFText.rowLabel, color: item.canRemoveAudio ? VFColor.textPrimary : VFColor.textTertiary)
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        Text("·").accessibilityHidden(true)
                        Text(LibraryCardModel.durationText(item.duration))
                        if item.hasSummary {
                            Text("·").accessibilityHidden(true)
                            Text("Summary")
                        }
                        if let reason = item.blockedReason {
                            Text("·").accessibilityHidden(true)
                            Text(reason)
                        }
                    }
                    .vfText(VFText.meta, color: VFColor.textTertiary)
                }
                Spacer(minLength: 8)
                Text(StorageMath.text(bytes: item.byteCount))
                    .vfText(VFText.meta, color: VFColor.textSecondary)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.canRemoveAudio)
        .accessibilityLabel([
            item.title,
            StorageMath.text(bytes: item.byteCount),
            SpokenFormat.duration(item.duration),
            item.blockedReason ?? (isSelected ? "Selected" : "Not selected"),
        ].joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Action bar

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button {
                confirmRemove = true
            } label: {
                Text(selected.isEmpty
                     ? "Select recordings to free space"
                     : "Remove audio · \(StorageMath.text(bytes: selectedBytes))")
            }
            .buttonStyle(VFPrimaryPillStyle())
            .disabled(selected.isEmpty || isWorking)
            .opacity(selected.isEmpty || isWorking ? 0.6 : 1)
            .accessibilityIdentifier("storage.remove")
        }
        .padding(.horizontal, VFSpace.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                colors: [VFColor.background.opacity(0), VFColor.background, VFColor.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: Data

    private func reload() {
        items = recordings.compactMap { recording in
            guard recording.hasAudio else { return nil }
            return StorageItem(
                id: recording.id,
                title: LibraryCardModel(recording: recording).title,
                createdAt: recording.createdAt,
                duration: recording.duration,
                byteCount: services.storage.audioByteCount(for: recording.id, fileName: recording.audioFileName),
                hasSummary: recording.currentSummary != nil,
                stage: recording.stage
            )
        }
        selected = selected.intersection(items.map(\.id))
    }

    private func removeSelected() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let ids = selected
        let targets = recordings.filter { ids.contains($0.id) }
        do {
            let freed = try LibraryActions(context: modelContext, services: services).removeAudio(from: targets)
            selected = []
            reload()
            let text = "Freed \(StorageMath.text(bytes: freed)). Transcripts and summaries are kept."
            message = text
            AccessibilityNotification.Announcement(text).post()
        } catch {
            message = "Couldn't remove the audio: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        StorageView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
}
