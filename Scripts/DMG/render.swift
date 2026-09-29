import AppKit
import CoreText

// Packaging artwork uses the onboarding's light paper and ink, independent of build-host appearance.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let fontURL = URL(fileURLWithPath: "App/Resources/Fonts/GildaDisplay-Regular.ttf")
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil),
      let titleFont = NSFont(name: "GildaDisplay-Regular", size: 64) else {
    fatalError("Cannot load the Aero brand font")
}
let size = NSSize(width: 640, height: 300)
let paper = NSColor(srgbRed: 0.965, green: 0.969, blue: 0.984, alpha: 1)
let ink = NSColor(srgbRed: 0.067, green: 0.078, blue: 0.169, alpha: 1)
let blue = NSColor(srgbRed: 0.133, green: 0.188, blue: 0.961, alpha: 1)
var representations: [NSBitmapImageRep] = []
for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 300 * scale,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create DMG artwork") }
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    paper.setFill()
    NSRect(origin: .zero, size: size).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    ("Aero" as NSString).draw(in: NSRect(x: 32, y: size.height - 107, width: 576, height: 80),
                             withAttributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: paragraph])

    // A quiet, static dither at the edges leaves the two real Finder icons unobstructed.
    blue.withAlphaComponent(0.10).setFill()
    for row in 0..<28 {
        for column in 0..<12 {
            let x = CGFloat(column * 5 + 8)
            let y = CGFloat(row * 5 + 40)
            if (row * 7 + column * 11) % 13 < 3 && column < 10 - abs(row - 14) / 2 {
                NSRect(x: x, y: y, width: 1.4, height: 1.4).fill()
                NSRect(x: 640 - x, y: y, width: 1.4, height: 1.4).fill()
            }
        }
    }
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 294, y: 110))
    arrow.line(to: NSPoint(x: 346, y: 110))
    arrow.move(to: NSPoint(x: 338, y: 118))
    arrow.line(to: NSPoint(x: 346, y: 110))
    arrow.line(to: NSPoint(x: 338, y: 102))
    blue.setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    representations.append(bitmap)
}
guard let tiff = NSBitmapImageRep.representationOfImageReps(in: representations, using: .tiff, properties: [:]) else {
    fatalError("Cannot encode DMG artwork")
}
try tiff.write(to: output, options: .atomic)
