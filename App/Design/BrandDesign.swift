import AppKit
import CoreText
import SwiftUI

/// The brand's paper, ink and faces, used by the onboarding (docs/ONBOARDING.md › Presentation) and never by the
/// chrome, which keeps `BrowserPalette` and the system face.
struct BrandPalette {
    let scheme: ColorScheme
    var paper: Color { scheme == .dark ? Color(red: 0.043, green: 0.051, blue: 0.094) : Color(red: 0.965, green: 0.969, blue: 0.984) }
    var ink: Color { scheme == .dark ? Color(red: 0.933, green: 0.941, blue: 0.980) : Color(red: 0.067, green: 0.078, blue: 0.169) }
    var line: Color { scheme == .dark ? Color(red: 0.153, green: 0.169, blue: 0.259) : Color(red: 0.855, green: 0.867, blue: 0.910) }
    /// The one solid blue element of a view, links and the wind's ink on brand moments.
    var blue: Color { scheme == .dark ? Color(red: 0.541, green: 0.576, blue: 1) : Color(red: 0.133, green: 0.188, blue: 0.961) }
    /// The wind's ink when another picture sits on the stage.
    var graphite: Color { scheme == .dark ? Color(red: 0.549, green: 0.569, blue: 0.651) : Color(red: 0.345, green: 0.365, blue: 0.431) }
}

extension EnvironmentValues {
    var brand: BrandPalette { BrandPalette(scheme: colorScheme) }
}

/// Gilda Display for titles, bundled under the SIL Open Font License (`Resources/Fonts`); everything else uses the
/// system face. Registered for the process on first use.
enum BrandType {
    private static let registered: Bool = {
        if let url = Bundle.main.url(forResource: "GildaDisplay-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontURLs([url] as CFArray, .process, true, nil)
        }
        return true
    }()

    static func title(_ size: CGFloat) -> Font { _ = registered; return .custom("Gilda Display", fixedSize: size) }
    /// For shapes drawn into the wind.
    static func titleFont(_ size: CGFloat) -> NSFont {
        _ = registered
        return NSFont(name: "GildaDisplay-Regular", size: size) ?? .systemFont(ofSize: size)
    }
}

/// The feather of the alternate app icon (`Scripts/generate-app-icon.swift`, which draws the same one): bare quill,
/// downy afterfeather, two splits in the vane, the near vane denser than the far one. The onboarding's wind writes it.
enum BrandFeather {
    /// Draws the feather white on `context` into `rect`, whose shorter side it spans; `rect` is in a top-left space.
    static func draw(in context: CGContext, rect: CGRect) {
        let scale = min(rect.width, rect.height) / 100
        context.saveGState()
        context.translateBy(x: rect.midX - 50 * scale, y: rect.midY - 50 * scale)
        context.scaleBy(x: scale, y: scale)
        let angle = (-90.0 + 38) * .pi / 180, length = 86.0
        let bx = 50 - cos(angle) * length / 2, by = 50 - sin(angle) * length / 2
        func at(_ t: Double) -> CGPoint {
            let bow = sin(t * .pi) * 5
            return CGPoint(x: bx + cos(angle) * length * t - sin(angle) * bow, y: by + sin(angle) * length * t + cos(angle) * bow)
        }
        let splits: [Double: [(Double, Double)]] = [1: [(0.5, 0.55)], -1: [(0.63, 0.67), (0.33, 0.36)]]
        context.setLineCap(.round)
        for i in 14..<97 {
            let t = Double(i) / 100, p = at(t), q = at(t + 0.01), direction = atan2(q.y - p.y, q.x - p.x)
            let down = t < 0.24
            let vane = down ? 7 + (t - 0.14) * 60 : pow(sin(min(1, (t - 0.12) / 0.86) * .pi), 0.55) * 21
            for side in [1.0, -1.0] {
                let gaps = splits[side] ?? []
                if gaps.contains(where: { t >= $0.0 && t <= $0.1 }) { continue }
                let after = gaps.contains(where: { t > $0.0 && t < $0.0 + 0.08 }) ? 6.0 : 0
                let jitter = down ? sin(Double(i) * 12.9 + side) * 22 : 0
                let barb = direction + side * (38 + 20 * t + after + jitter) * .pi / 180, reach = vane * (side > 0 ? 1 : 0.8)
                // Relief: the far vane and the down are lighter, and every third barb draws a striation.
                let gray = (side > 0 ? 1 : 0.72) * (down ? 0.7 : 1) * (i % 3 == 0 ? 0.6 : 1)
                context.setStrokeColor(gray: gray, alpha: 1)
                context.setLineWidth(down ? 1.3 : 1.7)
                context.move(to: p)
                context.addQuadCurve(to: CGPoint(x: p.x + cos(barb) * reach, y: p.y + sin(barb) * reach),
                                     control: CGPoint(x: p.x + cos(barb - side * 0.18) * reach * 0.55, y: p.y + sin(barb - side * 0.18) * reach * 0.55))
                context.strokePath()
            }
        }
        context.setStrokeColor(gray: 1, alpha: 1)
        context.setLineWidth(2.4)
        context.move(to: at(0))
        for step in 1...50 { context.addLine(to: at(Double(step) / 50)) }
        context.strokePath()
        context.restoreGState()
    }
}
