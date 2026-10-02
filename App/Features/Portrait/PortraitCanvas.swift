import AppKit
import SwiftUI

/// The portrait itself: the backdrop, the page in its window, and the credit, drawn at `zoom` times the layout's
/// points. Previews draw it at their own size from the page's small copy, so a slider never redraws the full-size
/// picture; `ImageRenderer` draws it at 1 from the page itself for export. Both are the same picture.
struct PortraitCanvas: View {
    /// `nil` until the snapshot arrives; the frame shows `placeholder` meanwhile.
    let shot: PortraitShot?
    let placeholder: Color
    let style: PortraitStyle
    let layout: PortraitLayout
    let zoom: CGFloat
    let url: URL
    let wallpaper: CGImage?
    let siteColor: Color
    /// The title bar's appearance.
    let scheme: ColorScheme

    var body: some View {
        let canvas = CGSize(width: layout.canvas.width * zoom, height: layout.canvas.height * zoom)
        ZStack(alignment: .topLeading) {
            PortraitBackdrop(style: style, size: canvas, wallpaper: wallpaper, siteColor: siteColor)
            window
                .frame(width: layout.window.width * zoom, height: layout.window.height * zoom)
                .offset(x: layout.window.minX * zoom, y: layout.window.minY * zoom)
            if let credit = layout.credit {
                PortraitCredit(size: Self.creditSize(for: layout.canvas) * zoom, dark: PortraitBackdrop.wantsDarkInk(style, siteColor: siteColor))
                    .position(x: credit.x * zoom, y: credit.y * zoom)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        .environment(\.colorScheme, scheme)
    }

    /// Readable once the picture is shrunk to a post, never louder than the page.
    static func creditSize(for canvas: CGSize) -> CGFloat { min(max(12, canvas.width * 0.009), 28) }

    private var window: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius * zoom, style: .continuous)
        let depth = style.shadow * max(layout.canvas.width, layout.canvas.height) * 0.02 * zoom
        let titleBar = style.showsAddress ? PortraitLayout.titleBarHeight : 0
        let size = CGSize(width: layout.window.width, height: layout.window.height - titleBar)
        let page = CGSize(width: size.width * zoom, height: size.height * zoom)
        return VStack(spacing: 0) {
            if style.showsAddress {
                // Drawn at its own size, then scaled: its text and lights keep their proportions.
                PortraitTitleBar(url: url, scheme: scheme)
                    .frame(width: size.width)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: page.width, height: PortraitLayout.titleBarHeight * zoom, alignment: .topLeading)
            }
            ZStack {
                placeholder
                if let shot {
                    Image(decorative: zoom < 1 ? shot.preview : shot.image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .transition(.opacity)
                }
            }
            .frame(width: page.width, height: page.height)
        }
        .clipShape(shape)
        // A hairline keeps a white page apart from a pale backdrop.
        .overlay { shape.strokeBorder(.black.opacity(0.08), lineWidth: max(zoom, 0.5)) }
        .shadow(color: .black.opacity(style.shadow > 0 ? 0.12 + 0.2 * style.shadow : 0), radius: depth, y: depth * 0.45)
    }
}

/// What lies behind the page.
struct PortraitBackdrop: View {
    let style: PortraitStyle
    let size: CGSize
    let wallpaper: CGImage?
    let siteColor: Color

    var body: some View {
        switch style.backdrop {
        case .gradient:
            let (start, end) = Self.pair(style.tint)
            LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .aurora:
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.55, 0], [1, 0],
                [0, 0.42], [0.62, 0.55], [1, 0.38],
                [0, 1], [0.4, 1], [1, 1],
            ], colors: Self.aurora(style.tint), smoothsColors: true)
        case .solid:
            Self.solid(style.tint)
        case .site:
            LinearGradient(colors: [siteColor.mix(with: .white, by: 0.3), siteColor.mix(with: .black, by: 0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .wallpaper:
            if let wallpaper {
                let blur = style.blursWallpaper ? max(size.width, size.height) * 0.025 : 0
                Image(decorative: wallpaper, scale: 1)
                    .resizable()
                    .scaledToFill()
                    // Blurring pulls transparency in from the edges: drawn larger, they stay outside.
                    .frame(width: size.width + 4 * blur, height: size.height + 4 * blur)
                    .blur(radius: blur, opaque: true)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Color(white: 0.5)
            }
        case .clear:
            Color.clear
        }
    }

    // The tint's colors: hues keep a light, airy start and a deeper neighbor; the ends are neutrals.

    private static func hue(_ value: Double, _ shift: Double) -> Double { (value + shift + 1).truncatingRemainder(dividingBy: 1) }

    static func pair(_ tint: PortraitStyle.Tint) -> (Color, Color) {
        switch tint {
        case .hue(let h): (Color(hue: h, saturation: 0.38, brightness: 0.99), Color(hue: hue(h, 0.07), saturation: 0.7, brightness: 0.86))
        case .white: (Color(white: 0.99), Color(white: 0.86))
        case .black: (Color(white: 0.24), Color(white: 0.04))
        }
    }

    static func solid(_ tint: PortraitStyle.Tint) -> Color {
        switch tint {
        case .hue(let h): Color(hue: h, saturation: 0.5, brightness: 0.9)
        case .white: Color(white: 0.96)
        case .black: Color(white: 0.07)
        }
    }

    static func aurora(_ tint: PortraitStyle.Tint) -> [Color] {
        switch tint {
        case .hue(let h):
            [Color(hue: hue(h, -0.05), saturation: 0.3, brightness: 1), Color(hue: h, saturation: 0.45, brightness: 0.98),
             Color(hue: hue(h, 0.1), saturation: 0.35, brightness: 1),
             Color(hue: hue(h, 0.12), saturation: 0.6, brightness: 0.95), Color(hue: hue(h, -0.03), saturation: 0.25, brightness: 1),
             Color(hue: hue(h, -0.1), saturation: 0.65, brightness: 0.9),
             Color(hue: hue(h, 0.04), saturation: 0.75, brightness: 0.82), Color(hue: hue(h, 0.16), saturation: 0.55, brightness: 0.93),
             Color(hue: hue(h, 0.02), saturation: 0.8, brightness: 0.78)]
        case .white:
            [Color(white: 1), Color(hue: 0.58, saturation: 0.06, brightness: 0.99), Color(hue: 0.9, saturation: 0.05, brightness: 1),
             Color(hue: 0.12, saturation: 0.06, brightness: 0.99), Color(white: 0.97), Color(hue: 0.55, saturation: 0.08, brightness: 0.95),
             Color(white: 0.9), Color(hue: 0.75, saturation: 0.06, brightness: 0.93), Color(white: 0.86)]
        case .black:
            [Color(white: 0.02), Color(hue: 0.65, saturation: 0.5, brightness: 0.2), Color(white: 0.04),
             Color(hue: 0.8, saturation: 0.45, brightness: 0.16), Color(white: 0.08), Color(hue: 0.55, saturation: 0.55, brightness: 0.22),
             Color(white: 0.03), Color(hue: 0.95, saturation: 0.4, brightness: 0.14), Color(white: 0.01)]
        }
    }

    /// Whether text on the backdrop reads better dark than light.
    static func wantsDarkInk(_ style: PortraitStyle, siteColor: Color) -> Bool {
        switch style.backdrop {
        case .gradient, .aurora, .solid:
            if case .white = style.tint { return true }
            return false
        case .site:
            guard let color = NSColor(siteColor).usingColorSpace(.sRGB) else { return false }
            return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent > 0.62
        case .clear: return true
        case .wallpaper: return false
        }
    }
}

/// “Captured with Aero”, small and faint, under the page.
private struct PortraitCredit: View {
    let size: CGFloat
    let dark: Bool

    var body: some View {
        HStack(spacing: size * 0.45) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: size * 1.35, height: size * 1.35)
            Text("Captured with Aero")
                .font(.system(size: size, weight: .medium))
        }
        .foregroundStyle(dark ? Color.black.opacity(0.5) : Color.white.opacity(0.78))
        .shadow(color: dark ? .clear : .black.opacity(0.18), radius: size * 0.3, y: size * 0.05)
        .fixedSize()
    }
}

/// A window's title bar above the page, with its address, as a portrait's frame.
private struct PortraitTitleBar: View {
    private static let lights: [Color] = [Color(red: 1, green: 0.373, blue: 0.341), Color(red: 0.996, green: 0.737, blue: 0.18),
                                          Color(red: 0.157, green: 0.784, blue: 0.251)]
    let url: URL
    let scheme: ColorScheme

    var body: some View {
        let palette = BrowserPalette(scheme: scheme)
        ZStack {
            HStack(spacing: 8) {
                ForEach(Self.lights.indices, id: \.self) { index in
                    Circle().fill(Self.lights[index]).frame(width: 12, height: 12)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            HStack(spacing: 5) {
                if url.scheme == "https" { Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold)) }
                Text(verbatim: url.siteName).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 12)
            .frame(height: 22)
            .background(palette.fill, in: Capsule())
            .padding(.horizontal, 90)
        }
        .frame(height: PortraitLayout.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(palette.sidebar)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
    }
}
