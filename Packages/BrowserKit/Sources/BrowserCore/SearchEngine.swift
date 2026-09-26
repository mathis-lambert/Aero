import Foundation

/// Where searches typed in the control bar go. Every engine offers an OpenSearch suggestion
/// endpoint, so one parser reads them all.
public enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google, duckDuckGo, bing, brave

    public static let `default` = SearchEngine.google

    public var id: Self { self }

    /// Brand names, the same in every language.
    public var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .brave: "Brave Search"
        }
    }

    public func searchURL(for query: String) -> URL? {
        switch self {
        case .duckDuckGo: Self.url(host: "duckduckgo.com", path: "/", query: ["q": query])
        case .google: Self.url(host: "www.google.com", path: "/search", query: ["q": query])
        case .bing: Self.url(host: "www.bing.com", path: "/search", query: ["q": query])
        case .brave: Self.url(host: "search.brave.com", path: "/search", query: ["q": query])
        }
    }

    public func suggestionsURL(for query: String) -> URL? {
        switch self {
        case .duckDuckGo: Self.url(host: "duckduckgo.com", path: "/ac/", query: ["q": query, "type": "list"])
        case .google: Self.url(host: "suggestqueries.google.com", path: "/complete/search", query: ["client": "firefox", "q": query])
        case .bing: Self.url(host: "api.bing.com", path: "/osjson.aspx", query: ["query": query])
        case .brave: Self.url(host: "search.brave.com", path: "/api/suggest", query: ["q": query])
        }
    }

    private static func url(host: String, path: String, query: KeyValuePairs<String, String>) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }
}

/// Reads an OpenSearch suggestion response, `["query", ["suggestion", …]]`. Responses are
/// untrusted: only distinct, bounded strings that differ from the query are kept.
public enum SearchSuggestions {
    package static let maximumCount = 4
    package static let maximumLength = 200

    public static func parse(_ data: Data, query: String) -> [String] {
        guard let response = try? JSONSerialization.jsonObject(with: data) as? [Any],
              response.count >= 2, let entries = response[1] as? [Any] else { return [] }
        var seen: Set<String> = [query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        var suggestions: [String] = []
        for case let entry as String in entries {
            let suggestion = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suggestion.isEmpty, suggestion.count <= maximumLength, seen.insert(suggestion.lowercased()).inserted else { continue }
            suggestions.append(suggestion)
            if suggestions.count == maximumCount { break }
        }
        return suggestions
    }
}
