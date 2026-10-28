import SwiftUI

/// How much a chrome surface is glass. The more it matters, the more glass it is: what is selected is a full lens,
/// tinted and responsive to the pointer; what is picked with others, a faint clear one; what holds other surfaces, a
/// faint pane that lets them lead; what floats over the page, full glass its content reads on. See
/// docs/DESIGN.md › Glass.
enum GlassRole {
    /// The selected tab or favorite.
    case selection
    /// A favorite at rest: half-strength clear glass, still, letting the window through.
    case tile
    /// The address, a control of a panel, a website tile: full glass answering the pointer, `tint` coloring it a little.
    case control
    /// A control that is on: glass colored through with `tint`.
    case accent
    /// A tab or folder picked with ⌘ or ⇧.
    case hover
    /// An open folder around its tabs.
    case container
    /// A panel, prompt, bar or tooltip over the page, whose content must read over whatever the page shows.
    case panel
    /// The sidebar floating over the page.
    case sidebar
}

extension View {
    /// Draws this view on glass of the role's intensity, `tint` coloring a selection or a control a little and an accent
    /// through.
    /// With Reduce Transparency the surface is opaque, with the one hairline border.
    func browserGlass(_ role: GlassRole, tint: Color? = nil, radius: CGFloat) -> some View {
        modifier(BrowserGlass(role: role, tint: tint, radius: radius))
    }

    /// A colored light behind a glass surface, which the glass bends and spreads: the color of what the surface holds,
    /// glowing through it. Nothing with Reduce Transparency, where there is no glass to light.
    func glassGlow(_ color: Color, radius: CGFloat) -> some View {
        modifier(GlassGlow(color: color, radius: radius))
    }
}

private struct BrowserGlass: ViewModifier {
    let role: GlassRole
    let tint: Color?
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Behind the content, so a fraction of the glass leaves the content whole.
        content.background {
            if reduceTransparency {
                shape.fill(opaqueFill)
                    .overlay { shape.strokeBorder(role == .container ? .clear : palette.line) }
            } else {
                Color.clear.glassEffect(glass, in: shape).opacity(strength)
            }
        }
    }

    /// Glass has no strength of its own: a pane that holds others shows at a fraction of it.
    private var strength: Double {
        switch role {
        case .selection, .control, .accent, .panel, .sidebar: 1
        case .hover: 0.7
        case .tile: 0.5
        case .container: 0.4
        }
    }

    private var glass: Glass {
        let dark = palette.scheme == .dark
        switch role {
        case .selection: return .regular.tint(tint?.opacity(dark ? 0.26 : 0.14)).interactive()
        case .tile: return .clear
        case .control: return .regular.tint(tint?.opacity(dark ? 0.16 : 0.08)).interactive()
        case .accent: return .regular.tint(tint ?? .accentColor).interactive()
        case .hover, .container: return .clear
        case .panel, .sidebar: return .regular
        }
    }

    private var opaqueFill: Color {
        switch role {
        case .selection: palette.raised
        case .tile: palette.favoriteTile
        case .control: palette.fill
        case .accent: tint ?? .accentColor
        case .hover: palette.favoriteTileHover
        case .container: palette.hover
        case .panel: palette.raised
        case .sidebar: palette.sidebar
        }
    }
}

private struct GlassGlow: ViewModifier {
    let color: Color
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.background {
            if !reduceTransparency {
                // Low in the surface, as light rising through it; drawn behind, so the glass refracts it.
                RoundedRectangle(cornerRadius: radius)
                    .fill(color.opacity(palette.scheme == .dark ? 0.55 : 0.4))
                    .scaleEffect(x: 0.7, y: 0.55, anchor: .bottom)
                    .blur(radius: 7)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }
}
