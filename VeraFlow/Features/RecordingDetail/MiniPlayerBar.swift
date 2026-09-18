import SwiftUI

/// The design's mini player, pinned under Summary and Transcript so playback is reachable
/// without the Audio tab (design spec §4). Wraps `VFMiniPlayer` around the controller.
struct MiniPlayerBar: View {
    let player: AudioPlayerController

    var body: some View {
        if let message = player.errorMessage {
            Text(message)
                .vfText(VFText.meta, color: VFColor.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(VFColor.playerBar)
                .overlay(alignment: .top) {
                    Rectangle().fill(VFColor.border).frame(height: VFMetric.hairline)
                }
        } else {
            VFMiniPlayer(
                isPlaying: player.isPlaying,
                elapsed: timeText(player.currentTime),
                total: timeText(player.duration),
                progress: player.duration > 0 ? min(1, max(0, player.currentTime / player.duration)) : 0,
                rate: player.rateLabel,
                togglePlayback: { player.togglePlayPause() },
                cycleRate: { player.cycleRate() }
            )
            .disabled(!player.isLoaded)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player")
            .accessibilityValue("\(SpokenFormat.duration(player.currentTime)) of \(SpokenFormat.duration(player.duration))")
        }
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        LibraryCardModel.durationText(seconds)
    }
}
