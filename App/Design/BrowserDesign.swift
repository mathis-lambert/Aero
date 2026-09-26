import BrowserCore
import SwiftUI

/// The chrome's tokens (`docs/DESIGN.md`): every value repeated by
/// more than one feature lives here.
enum BrowserDesign {
    enum Radius {
        // Insets keep nested corners concentric with the outer window silhouette.
        static let window: CGFloat = 20
        static let xs: CGFloat = 4
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let page: CGFloat = window - BrowserDesign.pageInset
        static let floatingSidebar: CGFloat = window - BrowserDesign.floatingInset
    }

    /// The system face at the chrome sizes; the brand serif never appears in the chrome.
    enum Typography {
        static let chrome = Font.system(size: 13)
        static let label = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11)
        static let keycap = Font.system(size: 11, weight: .medium, design: .monospaced)
        /// Small close and disclosure glyphs inside rows.
        static let glyph = Font.system(size: 9, weight: .semibold)
        static let title = Font.system(size: 22, weight: .semibold)
        /// The control bar's field and its icon.
        static let field = Font.system(size: 15)
    }

    static let sidebarWidth: CGFloat = 224
    static let sidebarHeaderHeight: CGFloat = 52
    static let windowControlsWidth: CGFloat = 96
    static let sidebarRevealEdgeWidth: CGFloat = 8
    static let controlHeight: CGFloat = 32
    static let navigationButtonSize: CGFloat = 28
    static let tabRowHeight: CGFloat = 34
    /// Leading symbol or favicon column in rows.
    static let rowIconWidth: CGFloat = 18
    /// Horizontal inset of sidebar and list rows, and the gap between their icon and label.
    static let rowInset: CGFloat = 10
    static let pageInset: CGFloat = 6
    /// Margin of panels floating over the page: the revealed sidebar and the find bar.
    static let floatingInset: CGFloat = 12
    static let tabIconSize: CGFloat = 16
    static let pinnedIconSize: CGFloat = 22
    static let downloadIconSize: CGFloat = 24
    static let faviconCornerRatio: CGFloat = 0.22
    static let motion = Animation.spring(duration: 0.28, bounce: 0.08)
    /// Quick enough to follow the pointer; a fade, so it stays with Reduce Motion.
    static let hover = Animation.easeOut(duration: 0.12)
    /// Fades a page in once it has rendered; short so navigation never feels delayed.
    static let pageReveal = Animation.easeOut(duration: 0.18)
}

struct BrowserPalette: Equatable {
    let scheme: ColorScheme
    var sidebar: Color { scheme == .dark ? Color(white: 0.13) : Color(white: 0.93) }
    var canvas: Color { scheme == .dark ? Color(white: 0.085) : Color(white: 0.975) }
    /// Opaque, so it reads the same with Reduce Transparency.
    var raised: Color { scheme == .dark ? Color(white: 0.17) : .white }
    var ink: Color { scheme == .dark ? Color(red: 0.94, green: 0.93, blue: 0.89) : Color(red: 0.18, green: 0.20, blue: 0.19) }
    var secondary: Color { scheme == .dark ? Color(red: 0.65, green: 0.67, blue: 0.65) : Color(red: 0.39, green: 0.41, blue: 0.39) }
    /// The only divider and border color.
    var line: Color { ink.opacity(scheme == .dark ? 0.15 : 0.11) }
    /// Neutral fills over any chrome surface: hover, then fields and selected rows, then press.
    var hover: Color { ink.opacity(0.04) }
    var fill: Color { ink.opacity(0.06) }
    var pressed: Color { ink.opacity(0.10) }
    /// Errors and the find bar's no-match border; always paired with text.
    var miss: Color { scheme == .dark ? Color(red: 1, green: 0.54, blue: 0.36) : Color(red: 0.76, green: 0.25, blue: 0.05) }
}

extension EnvironmentValues {
    var palette: BrowserPalette { BrowserPalette(scheme: colorScheme) }
}

extension View {
    func browserSurface(fill: Color, border: Color, radius: CGFloat) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(border, lineWidth: 1)
            }
    }

    /// The shell spring, or no animation with Reduce Motion.
    func browserAnimation(value: some Equatable) -> some View {
        modifier(BrowserAnimation(animation: BrowserDesign.motion, value: value))
    }

    func pageRevealAnimation(value: some Equatable) -> some View {
        modifier(BrowserAnimation(animation: BrowserDesign.pageReveal, value: value))
    }

    /// Panels floating over the page: the revealed sidebar and the find bar.
    func floatShadow() -> some View {
        shadow(color: .black.opacity(0.2), radius: 20, x: 5, y: 4)
    }

    /// Centered panels: the control bar and the Settings window.
    func panelShadow() -> some View {
        shadow(color: .black.opacity(0.16), radius: 32, y: 16)
    }
}

private struct BrowserAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

struct Hairline: View {
    enum Axis { case horizontal, vertical }
    var axis = Axis.horizontal
    @Environment(\.palette) private var palette

    var body: some View {
        let line = Rectangle().fill(palette.line)
        switch axis {
        case .horizontal: line.frame(height: 1)
        case .vertical: line.frame(width: 1)
        }
    }
}

extension ProfileColor {
    var tint: Color {
        switch self {
        case .terracotta: Color(red: 0.70, green: 0.32, blue: 0.21)
        case .moss: Color(red: 0.31, green: 0.46, blue: 0.34)
        case .ocean: Color(red: 0.24, green: 0.43, blue: 0.63)
        case .plum: Color(red: 0.54, green: 0.35, blue: 0.53)
        case .graphite: Color(red: 0.43, green: 0.46, blue: 0.47)
        }
    }
    /// Brighter than the tint, which turns dull as a light on the dark canvas.
    var luminous: Color {
        switch self {
        case .terracotta: Color(red: 1, green: 0.48, blue: 0.32)
        case .moss: Color(red: 0.45, green: 0.82, blue: 0.56)
        case .ocean: Color(red: 0.38, green: 0.66, blue: 1)
        case .plum: Color(red: 0.82, green: 0.5, blue: 0.9)
        case .graphite: Color(red: 0.68, green: 0.73, blue: 0.76)
        }
    }

    /// The accent of light effects: luminous on the dark canvas, the tint on the light one.
    func light(in scheme: ColorScheme) -> Color { scheme == .dark ? luminous : tint }

    var label: LocalizedStringKey {
        switch self {
        case .terracotta: "Terracotta"
        case .moss: "Moss"
        case .ocean: "Ocean"
        case .plum: "Plum"
        case .graphite: "Graphite"
        }
    }
}

struct IconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var size: CGFloat = BrowserDesign.controlHeight
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BrowserDesign.Typography.chrome.weight(.medium))
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// The chrome's borderless buttons: the `hover` fill under the pointer and the `pressed` fill while
/// pressed, over whatever surface the label draws.
struct QuietButtonStyle: ButtonStyle {
    var radius = BrowserDesign.Radius.control

    func makeBody(configuration: Configuration) -> some View {
        PointerFeedback(isPressed: configuration.isPressed, radius: radius) { configuration.label }
    }
}

/// The buttons of panels and prompts; the prominent one, filled with the accent, is the default.
struct PanelButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
        PointerFeedback(isPressed: configuration.isPressed, radius: BrowserDesign.Radius.control) {
            configuration.label
                .font(BrowserDesign.Typography.chrome.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(palette.ink))
                .padding(.horizontal, 14)
                .frame(height: BrowserDesign.controlHeight)
                .background(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.fill), in: shape)
        }
    }
}

private struct PointerFeedback<Label: View>: View {
    let isPressed: Bool
    let radius: CGFloat
    @ViewBuilder let label: Label
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var palette

    var body: some View {
        let fill = isPressed ? palette.pressed : hovered && isEnabled ? palette.hover : .clear
        label
            .overlay {
                RoundedRectangle(cornerRadius: radius).fill(fill).allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { hovered = $0 }
            .animation(BrowserDesign.hover, value: hovered)
    }
}

struct ShortcutLabel: View {
    let text: String
    /// On an accent fill, such as a prominent button.
    var onAccent = false
    @Environment(\.palette) private var palette

    var body: some View {
        Text(verbatim: text)
            .font(BrowserDesign.Typography.keycap)
            .foregroundStyle(onAccent ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(onAccent ? .white.opacity(0.2) : palette.line, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.xs))
            .accessibilityHidden(true)
    }
}

/// The profile's emoji, or its initial, on its color.
struct ProfileBadge: View {
    let profile: BrowserProfile
    var size: CGFloat = 30
    var body: some View {
        Text(verbatim: profile.emoji ?? String(profile.name.prefix(1)).uppercased())
            .font(.system(size: size * (profile.emoji == nil ? 0.43 : 0.5), weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(profile.color.tint, in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}
