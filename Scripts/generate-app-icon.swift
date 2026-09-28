#!/usr/bin/env swift
// Generates every Aero icon in one pass, so the system icon and the alternates cannot drift apart:
//   App/Resources/AppIcon.icon/Assets  aero-a-light.svg and aero-a-dark.svg, the system icon layers
//   App/Resources/AppIcons             aero-<mark>-<palette>.svg, the alternates offered in Settings, and the
//                                      system icon's two again, which Settings draws as Automatic
//
//   swift Scripts/generate-app-icon.swift <GildaDisplay-Regular.ttf> [--boost n]
//   --boost thickens the A's hairlines (default 1.0) so its bar and serifs survive the dither.
//
// The capital A comes from Gilda Display, the brand serif (SIL Open Font License 1.1,
// https://github.com/google/fonts/tree/main/ofl/gildadisplay); the font itself is not stored in the repository.
// The dots are a halftone of a warped wind field (the "mistral" or "clouds" motif), so the
// icons match the brand surfaces. Marks are drawn in a 100-unit box scaled to a 1024 px canvas, y pointing down.

import CoreGraphics
import CoreText
import Foundation

let canvas = 1024.0, unit = canvas / 100, side = Int(canvas)
let minimumDotRadius = 0.35

enum Mark: String, CaseIterable { case a, feather }
enum Motif: String { case mistral, clouds }

struct Palette {
    let name: String
    let ground: String
    let ink: String
    /// When set, dots darker than `inkSplit` use this second ink: large dots in one colour, small ones in another.
    var deepInk: String? = nil
    var motif: Motif = .clouds
}
let inkSplit = 0.6

/// light and dark of the A are the system icon; every other mark and palette pair is an alternate.
let palettes: [Palette] = [
    Palette(name: "light", ground: "#f6f7fb", ink: "#2230f5", motif: .mistral),
    Palette(name: "dark", ground: "#0b0d18", ink: "#8a93ff"),
    Palette(name: "blue", ground: "#2230f5", ink: "#ffffff"),
    Palette(name: "bw", ground: "#ffffff", ink: "#111111", motif: .mistral),
    Palette(name: "wb", ground: "#0a0a0a", ink: "#f5f5f5"),
    Palette(name: "lavender", ground: "#efeafd", ink: "#5b3fd1", motif: .mistral),
    Palette(name: "sun", ground: "#ffd23f", ink: "#141a5c"),
    Palette(name: "terracotta", ground: "#f8eee7", ink: "#b35236", motif: .mistral),
    Palette(name: "olive", ground: "#eef1e8", ink: "#4f7557", motif: .mistral),
    Palette(name: "dawn", ground: "#fff4ec", ink: "#ff7a45", deepInk: "#2230f5", motif: .mistral),
    Palette(name: "aurora", ground: "#0b0d18", ink: "#7ef0c8", deepInk: "#8a93ff"),
]

struct Tuning { let cells: Double; let contrast: Double; let shade: Double?; let shadeMix: Double; let threshold: Double }
let tuning: [Mark: Tuning] = [
    .a: Tuning(cells: 110, contrast: 1.6, shade: 0.85, shadeMix: 0.4, threshold: 0.43),
    .feather: Tuning(cells: 110, contrast: 1.9, shade: nil, shadeMix: 0.35, threshold: 0.35),
]

// MARK: - Arguments

var positional: [String] = [], boost = 1.0
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let argument = iterator.next() {
    if argument == "--boost" { boost = iterator.next().flatMap(Double.init) ?? boost } else { positional.append(argument) }
}
guard positional.count == 1 else { fatalError("Usage: generate-app-icon.swift <GildaDisplay-Regular.ttf> [--boost n]") }
let fontURL = URL(fileURLWithPath: positional[0])
let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Resources")
let systemIconURL = resources.appendingPathComponent("AppIcon.icon/Assets", isDirectory: true)
let alternatesURL = resources.appendingPathComponent("AppIcons", isDirectory: true)

// MARK: - Grayscale layers in a y-down 100-unit box

final class Layer {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    init() {
        context.setFillColor(gray: 0, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        context.translateBy(x: 0, y: canvas); context.scaleBy(x: unit, y: -unit)
    }
    /// Brightness 0…1 at a canvas pixel; the first bitmap row is the top of the image.
    func value(_ x: Double, _ y: Double) -> Double {
        let px = min(side - 1, max(0, Int(x))), py = min(side - 1, max(0, Int(y)))
        return Double(context.data!.bindMemory(to: UInt8.self, capacity: side * side)[py * side + px]) / 255
    }
    /// The bounding box and centroid, in units, of the pixels brighter than `threshold`.
    func shape(above threshold: Double) -> (box: CGRect, centroid: CGPoint) {
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: side * side), limit = UInt8(threshold * 255)
        var minX = side, minY = side, maxX = -1, maxY = -1, sumX = 0.0, sumY = 0.0, count = 0.0
        for y in 0..<side {
            for x in 0..<side where pixels[y * side + x] > limit {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                sumX += Double(x); sumY += Double(y); count += 1
            }
        }
        guard count > 0 else { fatalError("The mark drew nothing") }
        let box = CGRect(x: Double(minX) / unit, y: Double(minY) / unit, width: Double(maxX - minX + 1) / unit, height: Double(maxY - minY + 1) / unit)
        return (box, CGPoint(x: (sumX / count + 0.5) / unit, y: (sumY / count + 0.5) / unit))
    }
}

/// Marks are framed by the shape they draw, not by how they are built: the longer side of the shape spans
/// `markExtent` units, and its centre sits between its bounding box and its centroid, so the bottom-heavy A rises
/// and the feather moves off its dense vane, as the eye expects.
let markExtent = 54.0, opticalWeight = 0.3

func framing(_ draw: (Layer) -> Void, threshold: Double) -> CGAffineTransform {
    let probe = Layer()
    draw(probe)
    let (box, centroid) = probe.shape(above: threshold)
    let scale = markExtent / max(box.width, box.height)
    let x = box.midX + (centroid.x - box.midX) * opticalWeight, y = box.midY + (centroid.y - box.midY) * opticalWeight
    return CGAffineTransform(translationX: 50, y: 50).scaledBy(x: scale, y: scale).translatedBy(x: -x, y: -y)
}

func drawA(_ layer: Layer) {
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor], let base = descriptors.first else {
        fatalError("Cannot read \(fontURL.path)")
    }
    let variation = [2003265652 /* wght */: 500.0, 1869640570 /* opsz */: 96.0] as CFDictionary
    let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variation] as CFDictionary), 80, nil)
    var characters: [UniChar] = Array("A".utf16), glyphs = [CGGlyph](repeating: 0, count: 1), advance = CGSize.zero
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1), let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        fatalError("The font has no capital A")
    }
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, 1)
    let g = layer.context
    // Glyph outlines point up: flip them back. The placement is rough; `framing` sizes and centres the drawn shape.
    g.translateBy(x: 50 - advance.width / 2, y: 81); g.scaleBy(x: 1, y: -1)
    g.setFillColor(gray: 1, alpha: 1); g.addPath(outline); g.fillPath()
    g.setStrokeColor(gray: 1, alpha: 1); g.setLineWidth(boost); g.setLineJoin(.round); g.addPath(outline); g.strokePath()
}

/// A contour feather: bare quill, downy afterfeather, two splits in the vane. In the shade layer the near vane is
/// denser than the far one, which gives it relief.
func drawFeather(_ layer: Layer, shade: Bool) {
    let g = layer.context, a = (-90.0 + 38) * .pi / 180, length = 74.0
    let bx = 50 - cos(a) * length / 2, by = 50 - sin(a) * length / 2
    func at(_ t: Double) -> CGPoint {
        let bow = sin(t * .pi) * 5
        return CGPoint(x: bx + cos(a) * length * t - sin(a) * bow, y: by + sin(a) * length * t + cos(a) * bow)
    }
    let splits: [Double: [(Double, Double)]] = [1: [(0.5, 0.55)], -1: [(0.63, 0.67), (0.33, 0.36)]]
    g.setLineCap(.round)
    for i in 14..<97 {
        let t = Double(i) / 100, p = at(t), q = at(t + 0.01), direction = atan2(q.y - p.y, q.x - p.x)
        let down = t < 0.24
        let vane = down ? 7 + (t - 0.14) * 60 : pow(sin(min(1, (t - 0.12) / 0.86) * .pi), 0.55) * 19
        for side in [1.0, -1.0] {
            let gaps = splits[side] ?? []
            if gaps.contains(where: { t >= $0.0 && t <= $0.1 }) { continue }
            let after = gaps.contains(where: { t > $0.0 && t < $0.0 + 0.08 }) ? 6.0 : 0
            let jitter = down ? sin(Double(i) * 12.9 + side) * 22 : 0
            let barb = direction + side * (38 + 20 * t + after + jitter) * .pi / 180, reach = vane * (side > 0 ? 1 : 0.8)
            // Every third barb is lighter, so the grain draws striations along the barbs.
            let alpha = shade ? (side > 0 ? 0.95 : 0.45) * (down ? 0.6 : 1) * (i % 3 == 0 ? 0.3 : 1) : 1
            g.setStrokeColor(gray: 1, alpha: alpha); g.setLineWidth(down ? 1.2 : 1.6)
            g.move(to: p)
            g.addQuadCurve(to: CGPoint(x: p.x + cos(barb) * reach, y: p.y + sin(barb) * reach),
                           control: CGPoint(x: p.x + cos(barb - side * 0.18) * reach * 0.55, y: p.y + sin(barb - side * 0.18) * reach * 0.55))
            g.strokePath()
        }
    }
    g.setStrokeColor(gray: 1, alpha: 1); g.setLineWidth(shade ? 1.4 : 2.4)
    g.move(to: at(0)); for step in 1...50 { g.addLine(to: at(Double(step) / 50)) }; g.strokePath()
}

// MARK: - Wind field (also drawn by App/Features/NewTab/Wind.metal)

func hash(_ x: Double, _ y: Double) -> Double {
    let h = UInt32(truncatingIfNeeded: Int64(x) &* 374761393 &+ Int64(y) &* 668265263)
    let m = (h ^ (h >> 13)) &* 1274126177
    return Double(m ^ (m >> 16)) / 4294967296
}
func noise(_ x: Double, _ y: Double) -> Double {
    let xi = x.rounded(.down), yi = y.rounded(.down), xf = x - xi, yf = y - yi
    let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
    let a = hash(xi, yi), b = hash(xi + 1, yi), c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v
}
func fbm(_ x: Double, _ y: Double) -> Double {
    var sum = 0.0, amplitude = 0.5, x = x, y = y
    for _ in 0..<4 { sum += amplitude * noise(x, y); x = x * 2.03 + 17.1; y = y * 2.03 + 3.7; amplitude *= 0.5 }
    return sum
}
func wind(_ motif: Motif, _ x: Double, _ y: Double) -> Double {
    let angle = 24.0 * .pi / 180, scale = canvas * 0.55, seed = 3.0
    let u = (x * cos(angle) + y * sin(angle)) / scale + seed * 13.1, v = (-x * sin(angle) + y * cos(angle)) / scale + seed * 7.7
    if motif == .clouds { return fbm(u * 1.2, v * 1.2) }
    let px = u * 0.45, py = v * 1.6
    return fbm(px + 1.9 * fbm(px, py), py + 1.9 * fbm(px + 5.2, py + 1.3))
}

// MARK: - Dots ("halftone": the radius grows with darkness) and output

struct Dot { let x: Double, y: Double, radius: Double, darkness: Double }

func dots(for mark: Mark, motif: Motif) -> [Dot] {
    let tune = tuning[mark]!, mask = Layer(), shade = Layer()
    let drawMask: (Layer) -> Void = { mark == .a ? drawA($0) : drawFeather($0, shade: false) }
    let frame = framing(drawMask, threshold: tune.threshold)
    for layer in [mask, shade] { layer.context.concatenate(frame) }
    drawMask(mask)
    if mark == .feather { drawFeather(shade, shade: true) }
    let pitch = canvas / tune.cells, count = Int(tune.cells.rounded(.up))
    var result: [Dot] = []
    for j in 0..<count {
        for i in 0..<count {
            let x = (Double(i) + 0.5) * pitch, y = (Double(j) + 0.5) * pitch
            guard mask.value(x, y) > tune.threshold else { continue }
            var value = (wind(motif, Double(i) * pitch, Double(j) * pitch) - 0.5) * tune.contrast + 0.5
            value = value * (1 - tune.shadeMix) + (1 - (tune.shade ?? shade.value(x, y))) * tune.shadeMix
            let darkness = 1 - min(1, max(0, value)), radius = darkness.squareRoot() * pitch * 0.58
            if radius > minimumDotRadius { result.append(Dot(x: x, y: y, radius: radius, darkness: darkness)) }
        }
    }
    return result
}

func svg(_ dots: [Dot], _ palette: Palette) -> String {
    func circles(_ selected: [Dot]) -> String {
        selected.map { String(format: "<circle cx=\"%.1f\" cy=\"%.1f\" r=\"%.2f\"/>", $0.x, $0.y, $0.radius) }.joined()
    }
    var body = "<rect width=\"\(side)\" height=\"\(side)\" fill=\"\(palette.ground)\"/>"
    if let deep = palette.deepInk {
        body += "<g fill=\"\(palette.ink)\">\(circles(dots.filter { $0.darkness <= inkSplit }))</g>"
        body += "<g fill=\"\(deep)\">\(circles(dots.filter { $0.darkness > inkSplit }))</g>"
    } else {
        body += "<g fill=\"\(palette.ink)\">\(circles(dots))</g>"
    }
    return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(side)\" height=\"\(side)\" viewBox=\"0 0 \(side) \(side)\">\(body)</svg>\n"
}

let systemPalettes: Set = ["light", "dark"]
var written = 0
for url in [systemIconURL, alternatesURL] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
for mark in Mark.allCases {
    var byMotif: [Motif: [Dot]] = [:]
    for palette in palettes {
        let marked = byMotif[palette.motif] ?? dots(for: mark, motif: palette.motif)
        byMotif[palette.motif] = marked
        let isSystemIcon = mark == .a && systemPalettes.contains(palette.name)
        let name = "aero-\(mark.rawValue)-\(palette.name).svg"
        // The system icon's layers cannot be read back from the compiled icon, so Settings gets its own copy.
        for folder in isSystemIcon ? [systemIconURL, alternatesURL] : [alternatesURL] {
            try svg(marked, palette).write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        written += 1
    }
}
print("\(written) icons written: 2 in \(systemIconURL.path) and \(alternatesURL.path), \(written - 2) more in \(alternatesURL.path)")
