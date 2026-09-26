import Foundation

/// An icon declaration read from a page, before validation.
public struct FaviconLink: Equatable, Sendable {
    public let rel: String
    public let href: String
    public let sizes: String?
    public let type: String?

    package init(rel: String, href: String, sizes: String?, type: String?) {
        self.rel = rel
        self.href = href
        self.sizes = sizes
        self.type = type
    }
}

public struct FaviconCandidate: Equatable, Sendable {
    /// Largest icon side, in pixels, the browser displays (two times an 18 pt symbol, rounded up).
    public static let targetPixelSize = 64
    package static let maximumCandidates = 8
    package static let maximumURLLength = 2048
    private static let conventionalTouchIconSize = 180
    private static let fallbackPath = "/favicon.ico"
    /// ImageIO cannot decode vector icons.
    private static let unsupportedTypes: Set = ["image/svg+xml"]
    private static let unsupportedExtensions: Set = ["svg"]

    public let url: URL
    /// `nil` when the page did not declare a usable size.
    package let pixelSize: Int?

    /// Validated candidates, best first, ending with the origin's conventional `/favicon.ico`.
    public static func ranked(from links: [FaviconLink], pageURL: URL) -> [FaviconCandidate] {
        guard NavigationInput.isWebURL(pageURL), var origin = URLComponents(url: pageURL, resolvingAgainstBaseURL: true) else { return [] }
        origin.path = fallbackPath
        origin.query = nil
        origin.fragment = nil
        // Ties keep the page's declaration order.
        let declared = links.compactMap(candidate).enumerated()
            .sorted { (rank($0.element.pixelSize), $0.offset) < (rank($1.element.pixelSize), $1.offset) }
            .map(\.element)
        let fallback = origin.url.map { FaviconCandidate(url: $0, pixelSize: nil) }
        var seen = Set<URL>()
        let unique = (declared + [fallback].compactMap(\.self)).filter { seen.insert($0.url).inserted }
        guard unique.count > maximumCandidates, let last = unique.last else { return unique }
        return unique.prefix(maximumCandidates - 1) + [last]
    }

    private static func candidate(from link: FaviconLink) -> FaviconCandidate? {
        let relations = Set(link.rel.lowercased().split(separator: " ").map(String.init))
        let isTouchIcon = relations.contains("apple-touch-icon") || relations.contains("apple-touch-icon-precomposed")
        guard relations.contains("icon") || isTouchIcon,
              link.href.count <= maximumURLLength,
              let url = URL(string: link.href), NavigationInput.isWebURL(url),
              !unsupportedTypes.contains(link.type?.lowercased() ?? ""),
              !unsupportedExtensions.contains(url.pathExtension.lowercased())
        else { return nil }
        let declaredSize = link.sizes.flatMap(largestSide)
        return FaviconCandidate(url: url, pixelSize: declaredSize ?? (isTouchIcon ? conventionalTouchIconSize : nil))
    }

    /// Parses `sizes` such as "16x16 32x32"; "any" and malformed values count as unknown.
    private static func largestSide(in sizes: String) -> Int? {
        sizes.lowercased().split(separator: " ").compactMap { size -> Int? in
            let sides = size.split(separator: "x").compactMap { Int($0) }
            guard sides.count == 2, let side = sides.max(), side > 0 else { return nil }
            return side
        }.max()
    }

    /// Sufficient sizes first (smallest sufficient wins), then unknown sizes, then smaller icons (largest first).
    private static func rank(_ size: Int?) -> Int {
        guard let size else { return 0 }
        return size >= targetPixelSize ? size - Int.max : Int.max - size
    }
}
