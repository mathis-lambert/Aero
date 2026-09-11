import BrowserCore
import SwiftUI

/// Small semantic vocabulary shared by the shell and its features.
enum BrowserDesign {
    enum Radius {
        // Insets keep nested corners concentric with the outer window silhouette.
        static let window: CGFloat = 20
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let page: CGFloat = window - BrowserDesign.pageInset
        static let floatingSidebar: CGFloat = window - BrowserDesign.floatingSidebarInset
    }
    static let bodyFont = Font.system(size: 13)
    static let sidebarWidth: CGFloat = 224
    static let controlHeight: CGFloat = 32
    static let navigationButtonSize: CGFloat = 28
    static let windowControlsWidth: CGFloat = 96
    static let sidebarRevealEdgeWidth: CGFloat = 8
    static let pageInset: CGFloat = 6
    static let floatingSidebarInset: CGFloat = 12
    static let sidebarHeaderHeight: CGFloat = 52
    static let motion = Animation.spring(duration: 0.28, bounce: 0.08)
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
}

struct BrowserPalette {
    let scheme: ColorScheme
    var sidebar: Color { scheme == .dark ? Color(white: 0.13) : Color(white: 0.93) }
    var canvas: Color { scheme == .dark ? Color(white: 0.085) : Color(white: 0.975) }
    var raised: Color { scheme == .dark ? Color(white: 0.17) : .white.opacity(0.8) }
    var ink: Color { scheme == .dark ? Color(red: 0.94, green: 0.93, blue: 0.89) : Color(red: 0.18, green: 0.20, blue: 0.19) }
    var secondary: Color { scheme == .dark ? Color(red: 0.65, green: 0.67, blue: 0.65) : Color(red: 0.39, green: 0.41, blue: 0.39) }
    var line: Color { ink.opacity(scheme == .dark ? 0.15 : 0.11) }
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

extension BrowserAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
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
                .font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size)
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.10 : 0), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .opacity(isEnabled ? 1 : 0.3)
    }
}

struct ShortcutLabel: View {
    let text: String
    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control / 2))
            .accessibilityHidden(true)
    }
}

struct ProfileBadge: View {
    let profile: BrowserProfile
    var size: CGFloat = 30
    var body: some View {
        Text(verbatim: String(profile.name.prefix(1)).uppercased())
            .font(.system(size: size * 0.43, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(profile.color.tint, in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}
