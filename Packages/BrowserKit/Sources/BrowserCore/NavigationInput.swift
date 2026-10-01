import Foundation

/// Where an address a page navigates to goes. See docs/OTHER_APPS.md › Links to other apps.
public enum NavigationTarget: Equatable, Sendable {
    /// Loads in the page: websites, extension pages, and frame-local `about:` and `blob:` documents.
    case page
    /// Belongs to another app, which opens only after the person confirms.
    case application
    /// Never loads and never leaves: local files, scripts, inline data and the browser's own pages.
    case blocked
}

public enum NavigationInput {
    /// Schemes a website may never navigate to or hand to another app.
    private static let blockedSchemes: Set<String> = ["file", "javascript", "data", "vbscript", InternalPage.scheme, "chrome-extension", "webkit-extension", "http", "https"]

    public static func target(of url: URL) -> NavigationTarget {
        if isWebURL(url) || isExtensionURL(url) { return .page }
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return .blocked }
        if scheme == "about" || scheme == "blob" { return .page }
        // What remains of the page schemes is malformed, such as `https:` without a host.
        return blockedSchemes.contains(scheme) ? .blocked : .application
    }

    public static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    /// An extension's own page, such as its options or onboarding.
    public static func isExtensionURL(_ url: URL) -> Bool {
        ["chrome-extension", "webkit-extension"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    /// Addresses a tab may hold: websites, extensions' pages and the browser's internal pages.
    public static func isTabURL(_ url: URL) -> Bool {
        isWebURL(url) || isExtensionURL(url) || InternalPage(url: url) != nil
    }

    /// Text naming an address rather than words to search: a scheme, a dot or localhost. The
    /// control bar never sends such text to a search engine for suggestions.
    public static func looksLikeAddress(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return false }
        return value.contains(":") || value.contains(".") || value.lowercased().hasPrefix("localhost")
    }

    /// The address `text` names, or `nil` when it should be searched instead, including text naming
    /// something a tab cannot open, such as `javascript:` or `file:`.
    public static func address(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
        let lowered = value.lowercased()
        if value.contains("://") || lowered.hasPrefix("javascript:") || lowered.hasPrefix("data:") {
            return URL(string: value).flatMap { isTabURL($0) ? $0 : nil }
        }
        let isLocal = lowered == "localhost" || ["localhost:", "localhost/", "127.0.0.1", "[::1]"].contains { lowered.hasPrefix($0) }
        guard isLocal || value.contains(".") else { return nil }
        return URL(string: (isLocal ? "http://" : "https://") + value).flatMap { isWebURL($0) ? $0 : nil }
    }
}
