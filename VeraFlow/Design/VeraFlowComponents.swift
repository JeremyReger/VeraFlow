//
//  VeraFlowComponents.swift
//  VeraFlow — the reusable pieces the redesign is built from
//
//  Every screen in the canvas is one of these arranged in a stack. If a screen
//  needs something that isn't here, add it here rather than inlining it.
//

import SwiftUI

// MARK: - Section label

/// The small tracked capitals above each group ("WHAT MATTERED", "TODAY").
public struct VFSectionLabel: View {
    private let title: String
    private let showsRule: Bool

    public init(_ title: String, showsRule: Bool = false) {
        self.title = title
        self.showsRule = showsRule
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .vfText(VFText.sectionLabel, color: VFColor.textTertiary)
            if showsRule {
                Rectangle()
                    .fill(VFColor.border)
                    .frame(height: VFMetric.hairline)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Icon button

public struct VFIconButton: View {
    private let systemName: String
    private let label: String
    private let bordered: Bool
    private let action: () -> Void

    public init(systemName: String, label: String, bordered: Bool = true, action: @escaping () -> Void) {
        self.systemName = systemName
        self.label = label
        self.bordered = bordered
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(VFColor.iconPrimary)
                .frame(width: VFMetric.iconButton, height: VFMetric.iconButton)
                .background(bordered ? VFColor.surface : .clear, in: Circle())
                .overlay {
                    if bordered { Circle().strokeBorder(VFColor.border, lineWidth: VFMetric.hairline) }
                }
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Primary pill

public struct VFPrimaryPillStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vfText(VFText.buttonLabel, color: VFColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: VFMetric.primaryPillHeight)
            .background(VFColor.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

public struct VFSecondaryPillStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vfText(VFText.rowLabel, color: VFColor.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(VFColor.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

// MARK: - Filter chip

public struct VFChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(VFFontName.sansSemiBold, size: 12.5, relativeTo: .caption))
                .foregroundStyle(isSelected ? VFColor.background : VFColor.textSecondary)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(isSelected ? VFColor.textPrimary : .clear, in: Capsule())
                .overlay { Capsule().strokeBorder(isSelected ? .clear : VFColor.border, lineWidth: VFMetric.hairline) }
        }
        .frame(minHeight: VFMetric.minHit)   // visual chip is 34, hit area stays 44
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Recording card

public struct VFRecordingCard: View {
    public struct Model {
        public let title: String
        public let snippet: String
        public let timeOfDay: String
        public let duration: String
        public let speakerCount: Int
        public let actionCount: Int

        public init(title: String, snippet: String, timeOfDay: String,
                    duration: String, speakerCount: Int, actionCount: Int) {
            self.title = title
            self.snippet = snippet
            self.timeOfDay = timeOfDay
            self.duration = duration
            self.speakerCount = speakerCount
            self.actionCount = actionCount
        }
    }

    private let model: Model
    public init(_ model: Model) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.title)
                    .vfText(VFText.cardTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.duration)
                    .vfText(VFText.meta, color: VFColor.textTertiary)
            }

            Text(model.snippet)
                .vfText(VFText.snippet, color: VFColor.textSecondary)
                .lineLimit(2)

            HStack(spacing: 7) {
                Text(model.timeOfDay)
                Text("·")
                Text("^[\(model.speakerCount) speaker](inflect: true)")
                if model.actionCount > 0 {
                    Text("·")
                    Text("^[\(model.actionCount) action](inflect: true)")
                        .font(.custom(VFFontName.sansSemiBold, size: 11.5, relativeTo: .caption))
                        .foregroundStyle(VFColor.accent)
                }
            }
            .vfText(VFText.meta, color: VFColor.textTertiary)
            .padding(.top, 2)
        }
        .padding(.horizontal, VFSpace.cardPaddingH)
        .padding(.vertical, VFSpace.cardPaddingV)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
        }
    }
}

// MARK: - Underline tabs

public struct VFTabs<Tab: Hashable>: View {
    private let tabs: [(tab: Tab, title: String)]
    @Binding private var selection: Tab
    @Namespace private var underline

    public init(tabs: [(tab: Tab, title: String)], selection: Binding<Tab>) {
        self.tabs = tabs
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs, id: \.tab) { item in
                Button {
                    withAnimation(VFMotion.tabSwitch) { selection = item.tab }
                } label: {
                    VStack(spacing: 9) {
                        Text(item.title.uppercased())
                            .vfText(VFText.tabLabel,
                                    color: selection == item.tab ? VFColor.textPrimary : VFColor.textTertiary)
                        Group {
                            if selection == item.tab {
                                Capsule().fill(VFColor.accent)
                                    .matchedGeometryEffect(id: "vf.tab", in: underline)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 2)
                    }
                }
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.tab ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: VFMetric.minHit, alignment: .bottom)
        .overlay(alignment: .bottom) {
            Rectangle().fill(VFColor.border).frame(height: VFMetric.hairline)
        }
    }
}

// MARK: - Speaker dot + name

public struct VFSpeakerTag: View {
    private let name: String
    private let index: Int
    private let timecode: String
    private let needsName: Bool
    private let rename: () -> Void

    public init(name: String, index: Int, timecode: String, needsName: Bool = false, rename: @escaping () -> Void) {
        self.name = name
        self.index = index
        self.timecode = timecode
        self.needsName = needsName
        self.rename = rename
    }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(VFColor.speaker(index))
                .frame(width: 7, height: 7)
            Button(action: rename) {
                Text(name.uppercased())
                    .vfText(VFText.speakerLabel, color: VFColor.speaker(index))
            }
            .accessibilityLabel(needsName ? "Name this speaker" : "Rename \(name)")
            Text(timecode)
                .vfText(VFText.meta, color: VFColor.textTertiary)
            if needsName {
                Text("NAME?")
                    .font(.custom(VFFontName.sansBold, size: 9.5, relativeTo: .caption2))
                    .tracking(1)
                    .foregroundStyle(VFColor.textTertiary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
            }
        }
    }
}

// MARK: - Waveform

/// `samples` are 0...1 amplitudes. `progress` is 0...1 and colours the played
/// portion; pass nil for an idle waveform.
public struct VFWaveform: View {
    private let samples: [CGFloat]
    private let progress: Double?
    private let height: CGFloat

    public init(samples: [CGFloat], progress: Double? = nil, height: CGFloat = 84) {
        self.samples = samples
        self.progress = progress
        self.height = height
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: VFMetric.waveformBarGap) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                let head = progress.map { Int(Double(samples.count) * $0) }
                Capsule()
                    .fill(colour(for: index, head: head))
                    .frame(width: VFMetric.waveformBarWidth,
                           height: max(6, value * height))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)      // the transport controls carry the semantics
    }

    private func colour(for index: Int, head: Int?) -> Color {
        guard let head else { return VFColor.waveformIdle }
        if index == head { return VFColor.waveformHead }
        return index < head ? VFColor.accent : VFColor.waveformIdle
    }
}

// MARK: - Settings row

public struct VFSettingsRow<Trailing: View>: View {
    private let title: String
    private let detail: String?
    private let trailing: Trailing

    public init(title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).vfText(VFText.rowLabel)
                if let detail {
                    Text(detail).vfText(VFText.meta, color: VFColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: 54)
    }
}

/// Groups of settings rows share one card with hairlines between.
public struct VFSettingsGroup<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, VFSpace.cardPaddingH)
            .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                    .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
            }
    }
}

public struct VFToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? VFColor.accent : VFColor.surfaceRaised)
                .overlay {
                    if !configuration.isOn {
                        Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline)
                    }
                }
                .frame(width: 50, height: 30)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? VFColor.onAccent : VFColor.textTertiary)
                        .frame(width: 24, height: 24)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .frame(minWidth: VFMetric.minHit, minHeight: VFMetric.minHit, alignment: .trailing)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

// MARK: - Mini player

public struct VFMiniPlayer: View {
    private let isPlaying: Bool
    private let elapsed: String
    private let total: String
    private let progress: Double
    private let rate: String
    private let togglePlayback: () -> Void
    private let cycleRate: () -> Void

    public init(isPlaying: Bool, elapsed: String, total: String, progress: Double,
                rate: String, togglePlayback: @escaping () -> Void, cycleRate: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.total = total
        self.progress = progress
        self.rate = rate
        self.togglePlayback = togglePlayback
        self.cycleRate = cycleRate
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VFColor.onAccent)
                    .frame(width: 46, height: 46)
                    .background(VFColor.accent, in: Circle())
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("player.playPause")

            VStack(spacing: 7) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(VFColor.borderStrong)
                        Capsule().fill(VFColor.accent)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(elapsed)
                    Spacer()
                    Text(total)
                }
                .vfText(VFText.meta, color: VFColor.textTertiary)
            }

            Button(action: cycleRate) {
                Text(rate)
                    .font(.custom(VFFontName.sansBold, size: 12.5, relativeTo: .caption))
                    .foregroundStyle(VFColor.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
            }
            .accessibilityLabel("Playback speed, currently \(rate)")
        }
        .padding(.horizontal, VFSpace.gutterTight)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(VFColor.playerBar)
        .overlay(alignment: .top) {
            Rectangle().fill(VFColor.border).frame(height: VFMetric.hairline)
        }
    }
}

// MARK: - Live indicator

public struct VFLiveChip: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: String
    public init(_ title: String = "RECORDING") { self.title = title }

    public var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(VFColor.danger)
                .frame(width: 8, height: 8)
                .opacity(dimmed ? 0.28 : 1)
                // Holds steady under Reduce Motion (spec §6).
                .onAppear { if !reduceMotion { withAnimation(VFMotion.pulse) { dimmed = true } } }
            Text(title)
                .font(.custom(VFFontName.sansBold, size: 10.5, relativeTo: .caption2))
                .tracking(1.6)
                .foregroundStyle(VFColor.dangerMuted)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(VFColor.danger.opacity(0.14), in: Capsule())
        .overlay { Capsule().strokeBorder(VFColor.danger.opacity(0.4), lineWidth: VFMetric.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title == "RECORDING" ? "Recording in progress" : title.capitalized)
    }
}

// MARK: - Reassurance line

/// "Everything stays on this iPhone." in italic serif with a lock glyph (spec §1, point 4).
public struct VFReassurance: View {
    private let text: String
    public init(_ text: String = "Everything stays on this iPhone.") { self.text = text }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VFColor.textTertiary)
                .accessibilityHidden(true)
            Text(text)
                .vfText(VFText.reassurance, color: VFColor.textSecondary)
        }
    }
}

// MARK: - Waveform mark

/// Seven bars with the centre one in accent: the first-run mark.
public struct VFWaveformMark: View {
    private let height: CGFloat
    private let heights: [CGFloat] = [0.32, 0.55, 0.8, 1.0, 0.8, 0.55, 0.32]
    public init(height: CGFloat = 48) { self.height = height }

    public var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(index == 3 ? VFColor.accent : VFColor.waveformPlayed)
                    .frame(width: 5, height: heights[index] * height)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Screen header

/// Tracked eyebrow over a serif title, with the screen's icon buttons trailing.
public struct VFScreenHeader<Trailing: View>: View {
    private let eyebrow: String?
    private let title: String
    private let trailing: Trailing

    public init(eyebrow: String? = nil, title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .vfText(VFText.sectionLabel, color: VFColor.textTertiary)
                }
                Text(title)
                    .vfText(VFText.screenTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// A styled text field: surface fill, hairline border, field radius.
public struct VFField<Trailing: View>: View {
    private let placeholder: String
    @Binding private var text: String
    private let identifier: String?
    private let trailing: Trailing

    /// `identifier` lands on the text field itself, so UI tests can find it as a text field.
    public init(
        _ placeholder: String,
        text: Binding<String>,
        identifier: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.placeholder = placeholder
        self._text = text
        self.identifier = identifier
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(VFColor.textTertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .vfText(VFText.rowLabel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(identifier ?? "")
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: VFMetric.minHit)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.field, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
        }
    }
}

/// The circular 56 pt secondary button that sits next to the Record pill.
public struct VFRoundButtonLabel: View {
    private let systemName: String
    public init(systemName: String) { self.systemName = systemName }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(VFColor.iconPrimary)
            .frame(width: VFMetric.primaryPillHeight, height: VFMetric.primaryPillHeight)
            .background(VFColor.surface, in: Circle())
            .overlay { Circle().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
    }
}
