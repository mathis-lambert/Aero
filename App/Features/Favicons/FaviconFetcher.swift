import BrowserCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downloads and downsamples site icons away from the main actor.
/// Requests carry no cookies or cache, so icon fetching never reveals a profile's identity.
struct FaviconFetcher: Sendable {
    static let maximumDownloadBytes = 512 * 1024
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 15
    private static let successStatus = 200

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        session = URLSession(configuration: configuration)
    }

    /// Returns a PNG of the first candidate that decodes, at most `targetPixelSize` on its longest side.
    @concurrent
    func icon(from candidates: [FaviconCandidate]) async -> Data? {
        for candidate in candidates {
            guard !Task.isCancelled else { return nil }
            if let data = await download(candidate.url), let icon = Self.downsampledPNG(from: data) { return icon }
        }
        return nil
    }

    private func download(_ url: URL) async -> Data? {
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == Self.successStatus,
                  response.expectedContentLength <= Int64(Self.maximumDownloadBytes) else { return nil }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maximumDownloadBytes { return nil }
            }
            return data
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
