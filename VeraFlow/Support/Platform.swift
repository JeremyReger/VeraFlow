import Foundation
import SwiftUI

/// The few places where the iPhone and the Mac differ in words or in SwiftUI modifiers (v1.1
/// plan item 15). Every screen is shared; these shims keep `#if os(...)` out of the screens.
enum Platform {
    #if os(macOS)
    static let isMac = true
    /// "this Mac" / "your Mac" in copy that names the device.
    static let deviceNoun = "Mac"
    /// The privacy page's glyph on the onboarding and Settings screens.
    static let deviceSymbol = "laptopcomputer"
    static let lockedDeviceSymbol = "lock.laptopcomputer"
    #else
    static let isMac = false
    static let deviceNoun = "iPhone"
    static let deviceSymbol = "iphone.gen3"
    static let lockedDeviceSymbol = "lock.iphone"
    #endif

    /// "this iPhone" / "this Mac".
    static var thisDevice: String { "this \(deviceNoun)" }
    /// "This iPhone" / "This Mac" at the start of a sentence.
    static var thisDeviceCapitalized: String { "This \(deviceNoun)" }
    /// "your iPhone" / "your Mac".
    static var yourDevice: String { "your \(deviceNoun)" }
    /// "iPhone Microphone" / "Mac Microphone" for a built-in input with no better name.
    static var builtInMicrophoneName: String { "\(deviceNoun) Microphone" }

    /// Where the microphone permission is changed: the app's page in Settings on iOS, the
    /// Microphone privacy pane in System Settings on the Mac.
    static var microphoneSettingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #else
        URL(string: "app-settings:")
        #endif
    }
}

extension View {
    /// `.toolbar(visibility, for: .navigationBar)`: the navigation bar placement exists only on
    /// iOS. The Mac keeps its window toolbar, which carries the sidebar toggle.
    @ViewBuilder
    func vfNavigationBar(_ visibility: Visibility) -> some View {
        #if os(iOS)
        toolbar(visibility, for: .navigationBar)
        #else
        self
        #endif
    }

    /// The navigation bar's background colour on iOS; nothing on the Mac.
    @ViewBuilder
    func vfNavigationBarBackground(_ color: Color) -> some View {
        #if os(iOS)
        toolbarBackground(color, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Sheet detents are an iPhone idea; a Mac sheet is a panel sized by `vfSheetSize`.
    @ViewBuilder
    func vfSheetDetents(_ detents: Set<PresentationDetent>, dragIndicator: Bool = false) -> some View {
        #if os(iOS)
        presentationDetents(detents)
            .presentationDragIndicator(dragIndicator ? .visible : .automatic)
        #else
        self
        #endif
    }

    /// A Mac sheet takes the size of its content, which for a screen built from spacers is
    /// nothing; give it a window-like size. No effect on iOS, where sheets fill the screen.
    @ViewBuilder
    func vfSheetSize(width: CGFloat = 520, height: CGFloat = 680) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }

    /// `textInputAutocapitalization(.never)`; the Mac has no automatic capitalisation setting.
    @ViewBuilder
    func vfNoAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
