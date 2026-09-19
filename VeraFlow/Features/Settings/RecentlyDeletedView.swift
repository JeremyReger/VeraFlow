import SwiftData
import SwiftUI

/// Settings → Storage → Recently Deleted (v1.1 plan item 10): trashed recordings with the days
/// left before the launch sweep removes them, Restore, Delete Now, and Empty.
struct RecentlyDeletedView: View {
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @State private var confirmEmpty = false
    @State private var errorMessage: String?

    private var trashed: [Recording] {
        recordings.filter(\.isTrashed).sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VFSpace.sectionGap) {
                if trashed.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 34))
                            .foregroundStyle(VFColor.textTertiary)
                            .accessibilityHidden(true)
                        Text("Nothing here")
                            .vfText(VFText.cardTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Deleted recordings stay here for \(Int(TrashPolicy.retention / 86_400)) days, then they're removed for good.")
                            .vfText(VFText.body, color: VFColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .accessibilityIdentifier("trash.empty")
                } else {
                    VFSettingsGroup {
                        ForEach(Array(trashed.enumerated()), id: \.element.id) { position, recording in
                            if position > 0 { VFHairline() }
                            row(recording)
                        }
                    }
                    Button(role: .destructive) {
                        confirmEmpty = true
                    } label: {
                        Text("Empty Recently Deleted")
                            .vfText(VFText.rowLabel, color: VFColor.danger)
                            .frame(maxWidth: .infinity, minHeight: VFMetric.minHit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trash.emptyAll")
                }
            }
            .padding(.horizontal, VFSpace.gutter)
            .padding(.top, 8)
            .padding(.bottom, VFSpace.bottomInset)
        }
        .background(VFColor.background.ignoresSafeArea())
        .navigationTitle("Recently Deleted")
        .toolbarTitleDisplayMode(.inline)
        .vfNavigationBar(.visible)
        .confirmationDialog("Delete every recording here for good?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                Task { await run { try await actions.emptyTrash() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Audio, transcripts, and summaries are removed. This can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var actions: LibraryActions {
        LibraryActions(context: modelContext, services: services)
    }

    private func row(_ recording: Recording) -> some View {
        let days = recording.deletedAt.map { TrashPolicy.daysRemaining(deletedAt: $0) } ?? 0
        let daysText = days == 1 ? "1 day left" : "\(days) days left"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LibraryCardModel(recording: recording).title)
                    .vfText(VFText.rowLabel)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(recording.createdAt, format: .dateTime.month(.abbreviated).day())
                    Text("·").accessibilityHidden(true)
                    Text(LibraryCardModel.durationText(recording.duration))
                        .accessibilityLabel(SpokenFormat.duration(recording.duration))
                    Text("·").accessibilityHidden(true)
                    Text(daysText)
                }
                .vfText(VFText.meta, color: VFColor.textTertiary)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Restore", systemImage: "arrow.uturn.backward") {
                    Task { await run { try await actions.restore(recording) } }
                }
                Button("Delete Now", systemImage: "trash", role: .destructive) {
                    Task { await run { try await actions.delete(recording) } }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(VFColor.iconPrimary)
                    .frame(width: VFMetric.minHit, height: VFMetric.minHit)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(recording.title)")
        }
        .padding(.vertical, 10)
        .frame(minHeight: 54)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trash.row")
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RecentlyDeletedView()
    }
    .modelContainer(PreviewData.container())
    .environment(\.services, .fakes())
}
