import AppKit
import XCTest

/// Reads rendered colors from element screenshots, for assertions that only pixels can answer.
/// Captures hold values in the display's color space, so the expected sRGB color is converted into
/// the capture's space before comparing.
struct ScreenshotColor {
    static let tolerance: CGFloat = 16 / 255

    let expected: NSColor

    init(red: Int, green: Int, blue: Int) {
        expected = NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// Whether the pixel at `point` (in the element's coordinates, points) shows the expected color.
    func isShown(in element: XCUIElement, at point: CGPoint) -> Bool {
        let frame = element.frame
        guard frame.width > 0, frame.height > 0,
              let cgImage = element.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let x = Int(point.x / frame.width * CGFloat(bitmap.pixelsWide))
        let y = Int(point.y / frame.height * CGFloat(bitmap.pixelsHigh))
        guard let sample = bitmap.colorAt(x: x, y: y),
              let target = expected.usingColorSpace(bitmap.colorSpace) else { return false }
        return abs(sample.redComponent - target.redComponent) <= Self.tolerance
            && abs(sample.greenComponent - target.greenComponent) <= Self.tolerance
            && abs(sample.blueComponent - target.blueComponent) <= Self.tolerance
    }
}
