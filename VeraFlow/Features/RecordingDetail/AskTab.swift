import SwiftData
import SwiftUI

/// The Ask tab (v1.1 plan item 11): a question box over one recording. Every answer cites a
/// moment you can play, or says the recording doesn't have it.
struct AskTab: View {
    let recording: Recording
    let player: AudioPlayerController
    let isUnlocked: Bool
    let onLocked: () -> Void

    @Environment(\.services) private var services
    @State private var controller: AskController?
    @State private var question = ""
    @FocusState private var isFieldFocused: Bool

    private var canAsk: Bool {
        ExportGate.canAsk(unlocked: isUnlocked, isSample: recording.source == .sample)
    }

    private var speakerNames: [String: String] {
        Dictionary(recording.speakers.map { ($0.key, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                content(controller)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(VFColor.background)
        .task {
            if controller == nil {
                let passages = AskController.passages(
                    segments: recording.orderedSegments.map { (index: $0.index, start: $0.start, end: $0.end, speakerKey: $0.speakerKey, text: $0.text) },
                    speakerNames: speakerNames
                )
                let controller = AskController(service: services.questions, passages: passages)
                self.controller = controller
                await controller.refreshAvailability()
            }
        }
    }

    @ViewBuilder
    private func content(_ controller: AskController) -> some View {
        if recording.segments.isEmpty {
            emptyState(title: "Nothing to ask yet", text: "Questions work once the transcript is ready.")
        } else if let availability = controller.availability, !availability.isAvailable {
            emptyState(title: "Ask needs Apple Intelligence", text: OnboardingView.summaryMessage(availability))
        } else if !canAsk {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 34))
                    .foregroundStyle(VFColor.textTertiary)
                    .accessibilityHidden(true)
                Text("Ask this recording")
                    .vfText(VFText.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Ask what was said about anything and get an answer with the moment to play. Part of the one-time unlock; try it free on the sample recording.")
                    .vfText(VFText.body, color: VFColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Unlock") { onLocked() }
                    .buttonStyle(VFPrimaryPillStyle())
                    .padding(.top, 6)
                    .accessibilityIdentifier("ask.unlock")
                Spacer()
            }
            .padding(.horizontal, VFSpace.gutter + 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VFSpace.listGap) {
                        if controller.exchanges.isEmpty {
                            suggestions(controller)
                        }
                        ForEach(controller.exchanges) { exchange in
                            exchangeCard(exchange)
                                .id(exchange.id)
                        }
                        Text("AI-generated from your recording. Check important details.")
                            .vfText(VFText.reassurance, color: VFColor.textSecondary)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, VFSpace.gutterTight)
                    .padding(.vertical, VFSpace.sectionGap)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: controller.exchanges.count) { _, _ in
                    if let last = controller.exchanges.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            questionBar(controller)
        }
    }

    private func emptyState(title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 34))
                .foregroundStyle(VFColor.textTertiary)
                .accessibilityHidden(true)
            Text(title)
                .vfText(VFText.cardTitle)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .vfText(VFText.body, color: VFColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, VFSpace.gutter + 8)
    }

    private func suggestions(_ controller: AskController) -> some View {
        let open = (try? recording.currentSummary?.payload()).map { payload -> [String] in
            switch payload {
            case .general(let summary): summary.openQuestions
            case .client(let summary): summary.openQuestions
            case .walkthrough: []
            }
        } ?? []
        let items = AskController.suggestions(openQuestions: open, speakerNames: recording.speakers.sorted { $0.key < $1.key }.map(\.displayName))
        return VStack(alignment: .leading, spacing: 10) {
            VFSectionLabel("Try asking")
            ForEach(items, id: \.self) { item in
                Button {
                    Task { await controller.ask(item) }
                } label: {
                    HStack {
                        Text(item).vfText(VFText.rowLabel).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(VFColor.accent)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, VFSpace.cardPaddingH)
                    .frame(minHeight: 50)
                    .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous)
                            .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.suggestion")
            }
        }
    }

    private func exchangeCard(_ exchange: AskExchange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exchange.question)
                .vfText(VFText.rowLabel)
                .accessibilityAddTraits(.isHeader)
            switch exchange.outcome {
            case .pending:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading the transcript…").vfText(VFText.meta, color: VFColor.textTertiary)
                }
            case .answered(let text, let citations):
                Text(text).vfText(VFText.summaryBody)
                HStack(spacing: 8) {
                    ForEach(citations, id: \.self) { time in
                        Button {
                            player.seek(to: time)
                            player.play()
                        } label: {
                            Label(TranscriptChunker.timestamp(time), systemImage: "play.circle")
                                .font(.caption.monospacedDigit())
                                .frame(minHeight: 28)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Play from \(SpokenFormat.duration(time))")
                    }
                }
            case .notFound(let closest):
                Text("Not found in this recording.")
                    .vfText(VFText.summaryBody, color: VFColor.textSecondary)
                if !closest.isEmpty {
                    Text("Closest lines")
                        .vfText(VFText.sectionLabel, color: VFColor.textTertiary)
                    ForEach(closest, id: \.index) { passage in
                        Button {
                            player.seek(to: passage.start)
                            player.play()
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(TranscriptChunker.timestamp(passage.start))
                                    .vfText(VFText.meta, color: VFColor.textTertiary)
                                    .monospacedDigit()
                                Text("\(passage.speakerDisplayName): \(passage.text)")
                                    .vfText(VFText.snippet, color: VFColor.textSecondary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Plays from this line")
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .vfText(VFText.snippet, color: VFColor.danger)
            }
        }
        .padding(.horizontal, VFSpace.cardPaddingH)
        .padding(.vertical, VFSpace.cardPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.exchange")
    }

    /// The field takes the whole width and the Ask button sits under it, full width, like every
    /// other primary action in the app (Jeremy, 2026-09-19: the arrow beside the field was a
    /// small target and cut the field short).
    private func questionBar(_ controller: AskController) -> some View {
        let canSend = AskController.canSend(question: question, isWorking: controller.isWorking)
        return VStack(spacing: 10) {
            TextField("Ask about this recording", text: $question)
                .vfText(VFText.rowLabel)
                .focused($isFieldFocused)
                .submitLabel(.send)
                .onSubmit { send(controller) }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(minHeight: VFMetric.minHit)
                .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VFRadius.field, style: .continuous)
                        .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
                }
                .accessibilityIdentifier("ask.field")
            Button(controller.isWorking ? "Asking…" : "Ask") {
                send(controller)
            }
            .buttonStyle(VFPrimaryPillStyle())
            // The pill keeps its shape when it can't be used; the dimming says so, and
            // VoiceOver hears "dimmed" from `disabled` (A-8).
            .opacity(canSend ? 1 : 0.45)
            .disabled(!canSend)
            .accessibilityIdentifier("ask.send")
        }
        .padding(.horizontal, VFSpace.gutterTight)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(VFColor.playerBar)
        .overlay(alignment: .top) {
            Rectangle().fill(VFColor.border).frame(height: VFMetric.hairline)
        }
    }

    /// Return on the keyboard sends the same way the button does, and keeps what was typed
    /// when it can't (an answer already running), instead of clearing the field.
    private func send(_ controller: AskController) {
        guard AskController.canSend(question: question, isWorking: controller.isWorking) else { return }
        let text = question
        question = ""
        Task { await controller.ask(text) }
    }
}
