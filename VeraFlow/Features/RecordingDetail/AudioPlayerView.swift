import SwiftUI

/// Play/pause, skip, and scrub controls bound to an `AudioPlayerController`.
struct AudioPlayerView: View {
    let player: AudioPlayerController
    @State private var scrubTime: TimeInterval = 0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: 12) {
            if let message = player.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : player.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(player.duration, 0.01),
                    onEditingChanged: { editing in
                        if editing {
                            scrubTime = player.currentTime
                            isScrubbing = true
                        } else {
                            player.seek(to: scrubTime)
                            isScrubbing = false
                        }
                    }
                )
                .disabled(!player.isLoaded)
                .accessibilityLabel("Playback position")

                HStack {
                    Text(timeText(isScrubbing ? scrubTime : player.currentTime))
                    Spacer()
                    Text(timeText(player.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                HStack(spacing: 36) {
                    Button {
                        player.skip(by: -15)
                    } label: {
                        Image(systemName: "gobackward.15").font(.title2)
                    }
                    .accessibilityLabel("Back 15 seconds")

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 52))
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier("player.playPause")

                    Button {
                        player.skip(by: 15)
                    } label: {
                        Image(systemName: "goforward.15").font(.title2)
                    }
                    .accessibilityLabel("Forward 15 seconds")
                }
                .buttonStyle(.plain)
                .disabled(!player.isLoaded)
            }
        }
        .padding(.vertical, 4)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: seconds >= 3_600 ? .hourMinuteSecond : .minuteSecond))
    }
}
