import Foundation

public enum NavigationInput {
    public static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    /// Addresses a tab may hold: websites and the browser's internal pages.
    public static func isTabURL(_ url: URL) -> Bool {
        isWebURL(url) || InternalPage(url: url) != nil
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
