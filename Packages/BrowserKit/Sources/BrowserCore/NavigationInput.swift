import Foundation

public enum NavigationInput {
    public enum Failure: Error { case empty, unsupportedScheme, invalidAddress }

    public static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty
    }

    /// Addresses a tab may hold: websites and the browser's internal pages.
    public static func isTabURL(_ url: URL) -> Bool {
        isWebURL(url) || InternalPage(url: url) != nil
    }

    public static func resolve(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw Failure.empty }
        let hasWhitespace = value.contains(where: \.isWhitespace)
        if !hasWhitespace {
            if value.contains("://") || value.lowercased().hasPrefix("javascript:") || value.lowercased().hasPrefix("data:") {
                guard let url = URL(string: value), isTabURL(url) else { throw Failure.unsupportedScheme }
                return url
            }
            let isLocal = value == "localhost" || value.hasPrefix("localhost:") || value.hasPrefix("localhost/") || value.hasPrefix("127.0.0.1") || value.hasPrefix("[::1]")
            if isLocal || value.contains(".") {
                guard let url = URL(string: (isLocal ? "http://" : "https://") + value), isWebURL(url) else {
                    throw Failure.invalidAddress
                }
                return url
            }
        }
        var search = URLComponents()
        search.scheme = "https"
        search.host = "duckduckgo.com"
        search.queryItems = [URLQueryItem(name: "q", value: value)]
        guard let url = search.url else { throw Failure.invalidAddress }
        return url
    }
}
