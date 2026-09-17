import SwiftUI

/// Top-level navigation. M0 launches straight into the Library; onboarding gates it from M7.
struct RootView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
        .environment(\.services, .fakes())
        .environment(AppState(services: .fakes()))
}
