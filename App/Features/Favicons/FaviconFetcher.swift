import BrowserCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads and downsamples site icons away from the main actor, through the anonymous session.
struct FaviconFetcher: Sendable {
    private static let maximumDownloadBytes = 512 * 1024
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 15

    private let session = URLSession.anonymous(requestTimeout: requestTimeout, resourceTimeout: resourceTimeout)

    /// Returns a PNG of the first candidate that decodes, at most `targetPixelSize` on its longest side.
    @concurrent
    func icon(from candidates: [FaviconCandidate]) async -> Data? {
        for candidate in candidates {
            guard !Task.isCancelled else { return nil }
            if let data = await download(candidate.url), let icon = Self.downsampledPNG(from: data) { return icon }
        }
        return nil
    }

    /// Streams to a temporary file: collecting bytes one at a time costs about 6 µs each, seconds for a
    /// large icon. The resource timeout bounds the transfer; the size is checked once it completes.
    private func download(_ url: URL) async -> Data? {
        do {
            let (file, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: file) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max <= Self.maximumDownloadBytes else { return nil }
            return try Data(contentsOf: file)
        } catch {
            // Icons are best effort: an unreachable icon only keeps the fallback.
            return nil
        }
    }

    /// Picks the largest frame (ICO files hold several) and scales it down without decoding it at full size.
    private static func downsampledPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frames = 0..<CGImageSourceGetCount(source)
        let largest = frames.max { pixelWidth(of: source, at: $0) < pixelWidth(of: source, at: $1) } ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: FaviconCandidate.targetPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, largest, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func pixelWidth(of source: CGImageSource, at index: Int) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    }
}
