import CoreGraphics
import Foundation

/// How a portrait frames the page: what it shows, on which backdrop, and how much room it leaves. Saved as a
/// preference, so the next capture looks like the last one. See docs/PORTRAIT.md.
struct PortraitStyle: Codable, Equatable {
    /// What of the page the portrait shows.
    enum Source: String, Codable, CaseIterable, Identifiable {
        /// What the tab shows, as it is scrolled.
        case visible
        /// The whole page, from its top, up to `PortraitShot.longestPage`.
        case fullPage
        var id: Self { self }
    }

    enum Backdrop: String, Codable, CaseIterable, Identifiable {
        /// Two neighboring hues of the tint, diagonally.
        case gradient
        /// Soft blooms of the tint and its neighbors.
        case aurora
        case solid
        /// The desktop picture behind the window, blurred or not.
        case wallpaper
        /// The page's own color: its theme color, else its favicon's.
        case site
        /// Transparent, for a picture to place on something else.
        case clear
        var id: Self { self }
        /// Whether the tint chooses its colors.
        var isTinted: Bool { self == .gradient || self == .aurora || self == .solid }
    }

    /// The color of the tinted backdrops: a hue, or the two neutrals at the slider's ends.
    enum Tint: Codable, Equatable {
        case hue(Double)
        case white
        case black
    }

    /// The picture's proportions; the page is never cropped to reach them, the backdrop grows instead.
    enum Aspect: String, Codable, CaseIterable, Identifiable {
        case fit, square, widescreen, standard, portrait, story
        var id: Self { self }
        /// Width over height, or `nil` to follow the page.
        var ratio: CGFloat? {
            switch self {
            case .fit: nil
            case .square: 1
            case .widescreen: 16.0 / 9
            case .standard: 4.0 / 3
            case .portrait: 4.0 / 5
            case .story: 9.0 / 16
            }
        }
    }

    static let paddingRange: ClosedRange<Double> = 0...0.2
    static let cornerRange: ClosedRange<Double> = 0...28

    var source = Source.visible
    var backdrop = Backdrop.gradient
    var tint = Tint.hue(0.6)
    var blursWallpaper = true
    var aspect = Aspect.fit
    /// The margin around the page, as a share of its longer side.
    var padding = 0.08
    /// In points of the page.
    var cornerRadius = 14.0
    /// 0 for none.
    var shadow = 0.5
    /// A window's title bar above the page, with its address.
    var showsAddress = false
    /// “Captured with Aero” under the page.
    var showsCredit = true
}

/// Where a portrait's parts go, in points of the page, from the page's size and the style.
struct PortraitLayout: Equatable {
    /// The title bar `PortraitStyle.showsAddress` adds above the page.
    static let titleBarHeight: CGFloat = 36
    /// The least room under the page for the credit, which then never touches it.
    static let creditBand: CGFloat = 44
    /// The largest picture rendered, in pixels: about 160 MB while it is drawn.
    static let maximumPixels: CGFloat = 40_000_000
    /// The longest side of a picture, in pixels: the GPU's largest texture.
    static let maximumSide: CGFloat = 16_384

    let canvas: CGSize
    /// The page, with its title bar when there is one.
    let window: CGRect
    /// Where the credit is centered, when it is shown.
    let credit: CGPoint?

    init(page: CGSize, style: PortraitStyle) {
        let framed = CGSize(width: page.width, height: page.height + (style.showsAddress ? Self.titleBarHeight : 0))
        let margin = (style.padding * max(framed.width, framed.height)).rounded()
        // The credit needs a band under the page; a narrow margin grows there only.
        let creditBand = style.showsCredit ? max(margin, Self.creditBand) : margin
        var canvas = CGSize(width: framed.width + 2 * margin, height: framed.height + margin + creditBand)
        if let ratio = style.aspect.ratio {
            if canvas.width / canvas.height < ratio { canvas.width = (canvas.height * ratio).rounded() }
            else { canvas.height = (canvas.width / ratio).rounded() }
        }
        // Centered in the room the credit leaves, which keeps the margins even when there is no credit.
        let extra = canvas.height - framed.height - margin - creditBand
        let window = CGRect(x: ((canvas.width - framed.width) / 2).rounded(), y: margin + (extra / 2).rounded(),
                            width: framed.width, height: framed.height)
        self.canvas = canvas
        self.window = window
        credit = style.showsCredit ? CGPoint(x: canvas.width / 2, y: (window.maxY + canvas.height) / 2) : nil
    }

    /// The pixels per point a picture is rendered at: the display's, unless that would exceed the limits.
    func scale(preferred: CGFloat) -> CGFloat { Self.scale(of: canvas, preferred: preferred) }

    static func scale(of size: CGSize, preferred: CGFloat) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return preferred }
        return min(preferred, (maximumPixels / (size.width * size.height)).squareRoot(), maximumSide / max(size.width, size.height))
    }
}
