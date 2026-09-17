import ActivityKit
import SwiftUI
import WidgetKit

/// Recording status on the Lock Screen / Notification Center and in the Dynamic Island.
/// Status only: timer, Recording/Paused, bookmark count. Tapping opens the app.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingBanner(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        StatusIcon(isPaused: context.state.isPaused)
                        Text(context.state.isPaused ? "Paused" : "Recording")
                            .font(.headline)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingTimer(state: context.state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        BookmarkCount(count: context.state.bookmarkCount)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                StatusIcon(isPaused: context.state.isPaused)
            } compactTrailing: {
                RecordingTimer(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 56)
            } minimal: {
                StatusIcon(isPaused: context.state.isPaused)
            }
        }
    }
}

/// Lock Screen / Notification Center banner.
private struct RecordingBanner: View {
    let title: String
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            StatusIcon(isPaused: state.isPaused)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isPaused ? "Paused" : "Recording")
                    .font(.headline)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                BookmarkCount(count: state.bookmarkCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RecordingTimer(state: state)
                .font(.title2.monospacedDigit().weight(.semibold))
        }
        .padding()
    }
}

/// Counts up on its own; freezes at `pausedAt` while paused. No updates needed to tick.
private struct RecordingTimer: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.startedAt...Date.distantFuture,
            pauseTime: state.pausedAt,
            countsDown: false,
            showsHours: true
        )
        .multilineTextAlignment(.trailing)
    }
}

private struct StatusIcon: View {
    let isPaused: Bool

    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "record.circle.fill")
            .foregroundStyle(isPaused ? Color.orange : Color.red)
            .accessibilityLabel(isPaused ? "Paused" : "Recording")
    }
}

private struct BookmarkCount: View {
    let count: Int

    var body: some View {
        switch count {
        case 0: Text("No bookmarks")
        case 1: Text("1 bookmark")
        default: Text("\(count) bookmarks")
        }
    }
}
