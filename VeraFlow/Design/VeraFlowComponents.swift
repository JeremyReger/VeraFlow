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
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            // Padding to a minimum, not a fixed height: a label that outgrows the capsule should
            // grow the capsule, not hang out of it (Jeremy, 2026-09-20).
            .padding(.vertical, 14)
            .frame(minHeight: VFMetric.primaryPillHeight)
            .background(VFColor.accent, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

public struct VFSecondaryPillStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .vfText(VFText.rowLabel, color: VFColor.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .frame(minHeight: 54)
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
                .padding(.vertical, 8)
                .frame(minHeight: 34)
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

/// How the tab strip answers a reader who has turned text up. Kept out of `VFTabs` so it can be
/// tested without a running view, and so the strip and the pill beside it read the one constant.
public enum VFTabMetrics {
    /// Where the strip's own labels stop growing. Nothing else is clamped — the transcript, the
    /// summary and the action items scale the whole way — and the strip is clamped only so that
    /// reaching Audio doesn't mean scrolling past two screens of "TRANSCRIPT". This is still an
    /// accessibility size: about 1.7x the default, not a refusal to scale.
    public static let maximumLabelSize: DynamicTypeSize = .accessibility1

    public static func clamped(_ size: DynamicTypeSize) -> DynamicTypeSize {
        min(size, maximumLabelSize)
    }
}

/// The underline tab strip, with an optional control parked at the trailing edge — a view that
/// belongs with the tabs but shouldn't crowd them. It sits inside the strip rather than beside it
/// so the baseline hairline still runs the full width (Jeremy, 2026-09-20).
public struct VFTabs<Tab: Hashable, Trailing: View>: View {
    private let tabs: [(tab: Tab, title: String)]
    @Binding private var selection: Tab
    private let trailing: Trailing
    /// One namespace per candidate below: `ViewThatFits` builds every candidate in order to
    /// measure it, and two live views claiming the same matched-geometry id is a runtime warning.
    @Namespace private var plainUnderline
    @Namespace private var scrollingUnderline

    public init(
        tabs: [(tab: Tab, title: String)],
        selection: Binding<Tab>,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.tabs = tabs
        self._selection = selection
        self.trailing = trailing()
    }

    public var body: some View {
        // Measured rather than guessed at: whether four tracked-capital labels fit depends on the
        // text size, the device width and the words themselves, and a hardcoded size threshold
        // would be wrong on an iPhone SE and wasteful on a Pro Max. The strip is used as it always
        // was whenever it fits; only when it doesn't does it scroll sideways, which is what it now
        // does instead of breaking a word in half ("SU MM A…", Jeremy 2026-09-20).
        ViewThatFits(in: .horizontal) {
            strip(in: plainUnderline)
            // `fixedSize` vertically because a ScrollView is greedy on both axes: without it a
            // horizontal one still stretches to whatever height it is offered.
            ScrollView(.horizontal, showsIndicators: false) { strip(in: scrollingUnderline) }
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: VFMetric.minHit, alignment: .bottom)
        .overlay(alignment: .bottom) {
            // Outside the scroll view, so the hairline spans the screen rather than the labels.
            Rectangle().fill(VFColor.border).frame(height: VFMetric.hairline)
        }
    }

    private func strip(in underline: Namespace.ID) -> some View {
        // Bottom-aligned: the tab underlines sit on the hairline, and a taller trailing control
        // lines up with them instead of dragging the labels upward.
        HStack(alignment: .bottom, spacing: 22) {
            ForEach(tabs, id: \.tab) { item in
                Button {
                    withAnimation(VFMotion.tabSwitch) { selection = item.tab }
                } label: {
                    VStack(spacing: 9) {
                        Text(item.title.uppercased())
                            .vfText(VFText.tabLabel,
                                    color: selection == item.tab ? VFColor.textPrimary : VFColor.textTertiary)
                            // One line at its natural width. A tracked capital label that runs
                            // past the edge scrolls out of view; it never breaks mid-word.
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
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
                // Without this the Mac draws every tab as a bordered button, which is not the design.
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.tab ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 8)
            trailing
        }
        // The strip is the only thing clamped, and the trailing pill inherits the same ceiling
        // so it never outgrows the labels beside it.
        .dynamicTypeSize(...VFTabMetrics.maximumLabelSize)
    }
}

extension VFTabs where Trailing == EmptyView {
    public init(tabs: [(tab: Tab, title: String)], selection: Binding<Tab>) {
        self.init(tabs: tabs, selection: selection) { EmptyView() }
    }
}

/// A small capsule that switches to a view, for a destination that doesn't fit the tab strip.
/// Reads as "not one of the tabs" while still behaving like one.
public struct VFTabPill: View {
    private let title: String
    private let systemImage: String
    private let isSelected: Bool
    private let action: () -> Void
    /// The glyph grew with nothing when the label grew, and ended up a speck beside it.
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 11

    public init(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: glyphSize, weight: .semibold))
                Text(title.uppercased())
                    .vfText(VFText.tabLabel, color: isSelected ? VFColor.onAccent : VFColor.textSecondary)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? VFColor.onAccent : VFColor.textSecondary)
            .padding(.horizontal, 12)
            // Padding and a minimum, not a fixed height: at larger text sizes a 30 pt frame left
            // the label hanging out of its own capsule (Jeremy, 2026-09-20).
            .padding(.vertical, 6)
            .frame(minHeight: 30)
            .background {
                if isSelected {
                    Capsule().fill(VFColor.accent)
                } else {
                    Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Speaker dot + name

public struct VFSpeakerTag: View {
    private let name: String
    private let index: Int
    private let timecode: String
    private let needsName: Bool
    private let rename: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 7

    public init(name: String, index: Int, timecode: String, needsName: Bool = false, rename: @escaping () -> Void) {
        self.name = name
        self.index = index
        self.timecode = timecode
        self.needsName = needsName
        self.rename = rename
    }

    public var body: some View {
        // One row normally, two once the text is large: a speaker name, a timecode and the NAME?
        // chip side by side leave the name too little width, and it breaks in the middle of a
        // word ("SPEAK ER 1", Jeremy 2026-09-20). Stacking gives the name the full width back.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            HStack(spacing: 8) {
                Circle()
                    .fill(VFColor.speaker(index))
                    .frame(width: dotSize, height: dotSize)
                Button(action: rename) {
                    Text(name.uppercased())
                        .vfText(VFText.speakerLabel, color: VFColor.speaker(index))
                }
                .accessibilityLabel(needsName ? "Name this speaker" : "Rename \(name)")
            }
            HStack(spacing: 8) {
                Text(timecode)
                    .vfText(VFText.meta, color: VFColor.textTertiary)
                if needsName {
                    Text("NAME?")
                        .font(.custom(VFFontName.sansBold, size: 9.5, relativeTo: .caption2))
                        .tracking(1)
                        .foregroundStyle(VFColor.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minHeight: 20)
                        .overlay { Capsule().strokeBorder(VFColor.borderStrong, lineWidth: VFMetric.hairline) }
                }
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

/// A settings row whose trailing control is the switch: the toggle's label is drawn as the row
/// title, so VoiceOver hears one switch with that name, not a text plus an unnamed switch.
public struct VFToggleRowStyle: ToggleStyle {
    private let detail: String?
    public init(detail: String? = nil) { self.detail = detail }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                configuration.label.vfText(VFText.rowLabel)
                if let detail {
                    Text(detail).vfText(VFText.meta, color: VFColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(VFToggleStyle())
                .labelsHidden()
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
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
    /// Where the finger or pointer is, as 0...1, and whether the drag has ended. Called
    /// continuously while dragging so the caller can show the position it would seek to; `nil`
    /// leaves the bar a read-only progress indicator.
    private let onScrub: ((Double, Bool) -> Void)?
    /// VoiceOver's increment/decrement on the position bar: -1 or +1.
    private let onScrubStep: ((Int) -> Void)?

    @State private var isDragging = false

    /// The row the line sits in. The line itself stays 3 pt; the row is tall enough to grab,
    /// because a gesture attached to a 3 pt view is not a target on either platform. This costs
    /// no height: the 46 pt play button already sets the row's height.
    private static let trackHeight: CGFloat = 24
    private static let lineHeight: CGFloat = 3
    private static let thumbSize: CGFloat = 11

    public init(isPlaying: Bool, elapsed: String, total: String, progress: Double,
                rate: String, togglePlayback: @escaping () -> Void, cycleRate: @escaping () -> Void,
                onScrub: ((Double, Bool) -> Void)? = nil, onScrubStep: ((Int) -> Void)? = nil) {
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.total = total
        self.progress = progress
        self.rate = rate
        self.togglePlayback = togglePlayback
        self.cycleRate = cycleRate
        self.onScrub = onScrub
        self.onScrubStep = onScrubStep
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

            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(VFColor.borderStrong)
                            .frame(height: Self.lineHeight)
                        Capsule().fill(VFColor.accent)
                            .frame(width: geo.size.width * progress, height: Self.lineHeight)
                        if onScrub != nil {
                            Circle()
                                .fill(VFColor.accent)
                                .frame(width: Self.thumbSize, height: Self.thumbSize)
                                .scaleEffect(isDragging ? 1.35 : 1)
                                .offset(x: Self.thumbX(progress: progress, width: geo.size.width))
                                .animation(.easeOut(duration: 0.12), value: isDragging)
                        }
                    }
                    // The whole row is the target, not just the line it draws.
                    .frame(width: geo.size.width, height: Self.trackHeight)
                    .contentShape(Rectangle())
                    .gesture(scrubGesture(width: geo.size.width), including: onScrub == nil ? .subviews : .all)
                }
                .frame(height: Self.trackHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(elapsed) of \(total)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: onScrubStep?(1)
                    case .decrement: onScrubStep?(-1)
                    @unknown default: break
                    }
                }

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

    /// minimumDistance 0 so a plain click or tap seeks, without having to drag.
    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onScrub, width > 0 else { return }
                isDragging = true
                onScrub(Self.fraction(value.location.x, width: width), false)
            }
            .onEnded { value in
                defer { isDragging = false }
                guard let onScrub, width > 0 else { return }
                onScrub(Self.fraction(value.location.x, width: width), true)
            }
    }

    static func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    /// Keeps the thumb's whole width on the track at both ends.
    static func thumbX(progress: Double, width: CGFloat) -> CGFloat {
        let travel = max(0, width - thumbSize)
        return min(max(0, width * progress - thumbSize / 2), travel)
    }
}

// MARK: - Live indicator

public struct VFLiveChip: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: String
    private let isLive: Bool

    /// `isLive` false is the paused look (spec §5): grey, no pulse.
    public init(_ title: String = "RECORDING", isLive: Bool = true) {
        self.title = title
        self.isLive = isLive
    }

    public var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isLive ? VFColor.danger : VFColor.textTertiary)
                .frame(width: 8, height: 8)
                .opacity(dimmed && isLive ? 0.28 : 1)
                // Holds steady under Reduce Motion (spec §6).
                .onAppear { if !reduceMotion, isLive { withAnimation(VFMotion.pulse) { dimmed = true } } }
            Text(title)
                .font(.custom(VFFontName.sansBold, size: 10.5, relativeTo: .caption2))
                .tracking(1.6)
                .foregroundStyle(isLive ? VFColor.dangerMuted : VFColor.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 30)
        .background(isLive ? VFColor.danger.opacity(0.14) : VFColor.surfaceRaised, in: Capsule())
        .overlay {
            Capsule().strokeBorder(isLive ? VFColor.danger.opacity(0.4) : VFColor.borderStrong, lineWidth: VFMetric.hairline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title == "RECORDING" ? "Recording in progress" : title.capitalized)
    }
}

// MARK: - Hairline

/// The one-point rule between rows in a settings card.
public struct VFHairline: View {
    public init() {}
    public var body: some View {
        Rectangle().fill(VFColor.separator).frame(height: VFMetric.hairline)
    }
}

// MARK: - Picker row

/// The 60 pt "MICROPHONE / iPhone Microphone" row on the Record screen: use it as a `Menu`
/// label. The eyebrow says what is being chosen, the value says what is chosen.
public struct VFPickerRowLabel: View {
    private let eyebrow: String
    private let value: String
    private let systemName: String
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .footnote) private var chevronSize: CGFloat = 12

    public init(eyebrow: String, value: String, systemName: String) {
        self.eyebrow = eyebrow
        self.value = value
        self.systemName = systemName
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: .medium))
                .foregroundStyle(VFColor.iconPrimary)
                .frame(width: glyphWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .vfText(VFText.sectionLabel, color: VFColor.textTertiary)
                Text(value)
                    // Two lines: once the eyebrow above wrapped, a one-line value had no room
                    // left and truncated to "iPhone Micr…" (Jeremy, 2026-09-20).
                    .vfText(VFText.rowLabel)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: chevronSize, weight: .semibold))
                .foregroundStyle(VFColor.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, VFSpace.cardPaddingH)
        // The row already grew past 60 pt when the text wrapped, but with no vertical padding the
        // wrapped lines sat right on the card's border and read as overlapping it.
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: VFMetric.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: VFRadius.block, style: .continuous))
    }
}

// MARK: - Reassurance line

/// "Everything stays on this iPhone." in italic serif with a lock glyph (spec §1, point 4).
public struct VFReassurance: View {
    private let text: String
    /// `nil` reads "Everything stays on this iPhone." (or "this Mac"); the default lives in the
    /// body because a public default argument can't name the internal `Platform`.
    public init(_ text: String? = nil) { self.text = text ?? "Everything stays on \(Platform.thisDevice)." }

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
                .vfNoAutocapitalization()
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
