//
//  VeraFlowTokens.swift
//  VeraFlow — design tokens
//
//  Two appearances, one set of names. Light is "Chalk", dark is "Slate".
//  Nothing in the app should reference a hex directly; reference the token.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color helpers

public extension Color {

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Resolves against the current appearance at render time, so a single
    /// declaration covers both themes and follows the system setting.
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark))
                : UIColor(Color(hex: light))
        })
        #elseif canImport(AppKit)
        // The Mac resolves the same pair per appearance (v1.1 plan item 15).
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(Color(hex: dark))
                : NSColor(Color(hex: light))
        })
        #else
        self.init(hex: light)
        #endif
    }
}

// MARK: - Palette

public enum VFColor {

    // Surfaces
    public static let background       = Color(light: 0xF3F4F6, dark: 0x1B1D22)
    public static let surface          = Color(light: 0xFFFFFF, dark: 0x23262C)
    public static let surfaceRaised    = Color(light: 0xEDEFF2, dark: 0x2A2E35)
    public static let playerBar        = Color(light: 0xFFFFFF, dark: 0x202329)

    // Lines
    public static let separator        = Color(light: 0xEBEDF0, dark: 0x2B2F36)
    public static let border           = Color(light: 0xE1E4E9, dark: 0x32363E)
    public static let borderStrong     = Color(light: 0xD3D8DE, dark: 0x3C414A)

    // Text
    public static let textPrimary      = Color(light: 0x16181C, dark: 0xF2F4F7)
    public static let textSecondary    = Color(light: 0x4A5058, dark: 0xB4BAC4)
    public static let textTertiary     = Color(light: 0x5F666F, dark: 0x868E9A)
    /// Icon glyphs in chrome — one step stronger than secondary.
    public static let iconPrimary      = Color(light: 0x333941, dark: 0xDCE0E7)

    // Accent
    public static let accent           = Color(light: 0x2E5A8A, dark: 0x7EB6DE)
    /// Label or glyph sitting on top of an accent fill.
    public static let onAccent         = Color(light: 0xF3F4F6, dark: 0x1B1D22)

    // Status
    public static let danger           = Color(light: 0xB3261E, dark: 0xF0796B)
    public static let dangerMuted      = Color(light: 0x8C2019, dark: 0xF2A196)
    public static let success          = Color(light: 0x2E7D4F, dark: 0x8FC79B)
    public static let successFill      = Color(light: 0xE3F0E6, dark: 0x28382F)

    // Now-playing transcript block
    public static let nowPlayingFill   = Color(light: 0xEAF1F8, dark: 0x232A33)
    public static let nowPlayingBorder = Color(light: 0xC3D6E8, dark: 0x3A4654)

    // Waveform
    public static let waveformPlayed   = Color(light: 0x9AA1AA, dark: 0x4A505A)
    public static let waveformIdle     = Color(light: 0xCFD4DA, dark: 0x3A4049)
    public static let waveformHead     = Color(light: 0x16181C, dark: 0xF2F4F7)

    /// Speaker colours are authored per appearance, not derived by dimming —
    /// the warm set used in the first pass fell below 4.5:1 on a light ground.
    public static let speakerPalette: [Color] = [
        Color(light: 0x2E5A8A, dark: 0x7EB6DE),
        Color(light: 0x1E6E62, dark: 0x8FC79B),
        Color(light: 0x8A5A1E, dark: 0xE0A86A),
        Color(light: 0x6B4FA8, dark: 0xBFA6E8),
        Color(light: 0x9A3A6B, dark: 0xE79CC2)
    ]

    /// Stable per-recording assignment; wraps past five voices.
    public static func speaker(_ index: Int) -> Color {
        speakerPalette[((index % speakerPalette.count) + speakerPalette.count) % speakerPalette.count]
    }
}

// MARK: - Type

/// Both families ship with the app. Add the .ttf files to the target and list
/// them under `UIAppFonts` in Info.plist. Verify the PostScript names with
/// `UIFont.fontNames(forFamilyName:)` once before trusting them — a wrong name
/// silently falls back to San Francisco and the whole design flattens out.
public enum VFFontName {
    public static let serif           = "Newsreader-Regular"
    public static let serifItalic     = "Newsreader-Italic"
    public static let sansRegular     = "Manrope-Regular"
    public static let sansMedium      = "Manrope-Medium"
    public static let sansSemiBold    = "Manrope-SemiBold"
    public static let sansBold        = "Manrope-Bold"
}

public struct VFTextStyle: Sendable {
    public let font: Font
    public let tracking: CGFloat
    public let lineSpacing: CGFloat
    public let usesTabularFigures: Bool

    public init(font: Font, tracking: CGFloat = 0, lineSpacing: CGFloat = 0, usesTabularFigures: Bool = false) {
        self.font = font
        self.tracking = tracking
        self.lineSpacing = lineSpacing
        self.usesTabularFigures = usesTabularFigures
    }
}

public enum VFText {

    // Serif — anything the user reads rather than scans.
    public static let screenTitle = VFTextStyle(
        font: .custom(VFFontName.serif, size: 34, relativeTo: .largeTitle), tracking: -0.5)
    public static let recordingTitle = VFTextStyle(
        font: .custom(VFFontName.serif, size: 29, relativeTo: .title), tracking: -0.45, lineSpacing: 3)
    public static let cardTitle = VFTextStyle(
        font: .custom(VFFontName.serif, size: 20, relativeTo: .headline), tracking: -0.2, lineSpacing: 2)
    public static let summaryBody = VFTextStyle(
        font: .custom(VFFontName.serif, size: 17, relativeTo: .body), lineSpacing: 6)
    public static let transcriptBody = VFTextStyle(
        font: .custom(VFFontName.serif, size: 16.5, relativeTo: .body), lineSpacing: 6)
    public static let reassurance = VFTextStyle(
        font: .custom(VFFontName.serifItalic, size: 14.5, relativeTo: .footnote), lineSpacing: 3)
    public static let timerDisplay = VFTextStyle(
        font: .custom(VFFontName.serif, size: 62, relativeTo: .largeTitle),
        tracking: -1.2, usesTabularFigures: true)

    // Sans — labels, metadata, controls.
    public static let sectionLabel = VFTextStyle(
        font: .custom(VFFontName.sansSemiBold, size: 10.5, relativeTo: .caption2), tracking: 1.7)
    public static let tabLabel = VFTextStyle(
        font: .custom(VFFontName.sansBold, size: 12, relativeTo: .caption), tracking: 1.2)
    public static let speakerLabel = VFTextStyle(
        font: .custom(VFFontName.sansBold, size: 11.5, relativeTo: .caption), tracking: 0.7)
    public static let body = VFTextStyle(
        font: .custom(VFFontName.sansRegular, size: 14, relativeTo: .subheadline), lineSpacing: 4)
    public static let rowLabel = VFTextStyle(
        font: .custom(VFFontName.sansMedium, size: 14.5, relativeTo: .body))
    public static let snippet = VFTextStyle(
        font: .custom(VFFontName.sansRegular, size: 13, relativeTo: .footnote), lineSpacing: 4)
    public static let meta = VFTextStyle(
        font: .custom(VFFontName.sansRegular, size: 11.5, relativeTo: .caption),
        usesTabularFigures: true)
    public static let buttonLabel = VFTextStyle(
        font: .custom(VFFontName.sansBold, size: 15.5, relativeTo: .body), tracking: 0.15)
}

public struct VFTextModifier: ViewModifier {
    let style: VFTextStyle
    let color: Color?

    public func body(content: Content) -> some View {
        content
            .font(style.usesTabularFigures ? style.font.monospacedDigit() : style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .foregroundStyle(color ?? VFColor.textPrimary)
    }
}

public extension View {
    func vfText(_ style: VFTextStyle, color: Color? = nil) -> some View {
        modifier(VFTextModifier(style: style, color: color))
    }
}

// MARK: - Metrics

public enum VFSpace {
    /// Screen side gutter. Detail-screen chrome rows use `gutterTight`.
    public static let gutter: CGFloat = 20
    public static let gutterTight: CGFloat = 16
    public static let cardPaddingH: CGFloat = 16
    public static let cardPaddingV: CGFloat = 15
    public static let listGap: CGFloat = 10
    public static let sectionGap: CGFloat = 18
    public static let bottomInset: CGFloat = 30
}

public enum VFRadius {
    public static let field: CGFloat = 12
    public static let block: CGFloat = 14
    public static let card: CGFloat = 16
    public static let panel: CGFloat = 18
    public static let pill: CGFloat = 999
}

public enum VFMetric {
    /// Never draw a tappable thing smaller than this.
    public static let minHit: CGFloat = 44
    public static let iconButton: CGFloat = 44
    public static let primaryPillHeight: CGFloat = 56
    public static let hairline: CGFloat = 1
    public static let waveformBarWidth: CGFloat = 3
    public static let waveformBarGap: CGFloat = 2
}

public enum VFMotion {
    /// The live-recording dot and the in-progress ring.
    public static let pulse = Animation.easeInOut(duration: 1.7).repeatForever(autoreverses: true)
    public static let transcriptScroll = Animation.easeOut(duration: 0.28)
    public static let tabSwitch = Animation.easeInOut(duration: 0.2)
}
