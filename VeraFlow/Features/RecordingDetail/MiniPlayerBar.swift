import SwiftUI

/// The design's mini player, pinned under Summary and Transcript so playback is reachable
/// without the Audio tab (design spec §4). Wraps `VFMiniPlayer` around the controller.
struct MiniPlayerBar: View {
    let player: AudioPlayerController

    /// Where the drag is, while it lasts. The bar follows the finger or pointer and the elapsed
    /// time reads the position it would seek to; the player itself only moves when the drag ends,
    /// so scrubbing never fights the ticker (same shape as the Audio tab's waveform).
    @State private var scrubFraction: Double?

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
                elapsed: timeText(shownTime),
                total: timeText(player.duration),
                progress: shownProgress,
                rate: player.rateLabel,
                togglePlayback: { player.togglePlayPause() },
                cycleRate: { player.cycleRate() },
                onScrub: scrub,
                onScrubStep: { player.skip(by: Double($0) * 15) }
            )
            .disabled(!player.isLoaded)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Player")
            .accessibilityValue("\(SpokenFormat.duration(shownTime)) of \(SpokenFormat.duration(player.duration))")
        }
    }

    private func scrub(to fraction: Double, isFinal: Bool) {
        guard player.isLoaded, player.duration > 0 else {
            scrubFraction = nil
            return
        }
        if isFinal {
            player.seek(to: fraction * player.duration)
            scrubFraction = nil
        } else {
            scrubFraction = fraction
        }
    }

    /// The drag wins over the playhead while it is happening.
    private var shownProgress: Double {
        if let scrubFraction { return scrubFraction }
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    private var shownTime: TimeInterval {
        if let scrubFraction { return scrubFraction * player.duration }
        return player.currentTime
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        LibraryCardModel.durationText(seconds)
    }
}
