import CoreGraphics
import Foundation
import ImageIO

/// A small, alpha-aware color histogram favors the icon's colored mark over white/black padding.
struct FaviconColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double

    @concurrent
    static func extract(from data: Data) async -> FaviconColor? {
        let side = 32
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: side
              ] as CFDictionary) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var buckets = [Bucket](repeating: Bucket(), count: 512)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.1 else { continue }
            let r = min(1, Double(pixels[offset]) / 255 / alpha)
            let g = min(1, Double(pixels[offset + 1]) / 255 / alpha)
            let b = min(1, Double(pixels[offset + 2]) / 255 / alpha)
            let weight = alpha * (0.05 + max(r, g, b) - min(r, g, b))
            let index = min(7, Int(r * 8)) * 64 + min(7, Int(g * 8)) * 8 + min(7, Int(b * 8))
            buckets[index].weight += weight
            buckets[index].red += r * weight
            buckets[index].green += g * weight
            buckets[index].blue += b * weight
        }
        guard let dominant = buckets.max(by: { $0.weight < $1.weight }), dominant.weight > 0 else { return nil }
        return FaviconColor(red: dominant.red / dominant.weight,
                            green: dominant.green / dominant.weight,
                            blue: dominant.blue / dominant.weight)
    }

    private struct Bucket {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
    }
}
