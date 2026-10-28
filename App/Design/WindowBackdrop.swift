import BrowserCore
import SwiftUI

/// Behind the sidebar and the page: the desktop shows a little through the window, blurred, under the chrome's
/// color tinted by the space's. Opaque with Reduce Transparency. Switching spaces moves the tint with the page.
struct WindowBackdrop: ViewModifier {
    /// How much of the chrome's color covers the blurred desktop.
    private static let cover = 0.7
    private static let tint = (light: 0.08, dark: 0.12)

    let accent: SpaceColor
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.browserReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    palette.sidebar.opacity(reduceTransparency ? 1 : Self.cover)
                    accent.tint.opacity(palette.scheme == .dark ? Self.tint.dark : Self.tint.light)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: accent)
                .ignoresSafeArea()
            }
            .containerBackground(reduceTransparency ? AnyShapeStyle(palette.sidebar) : AnyShapeStyle(.regularMaterial), for: .window)
    }
}
