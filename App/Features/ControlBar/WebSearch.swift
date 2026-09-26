import BrowserCore
import Foundation

/// The chosen engine's search and suggestion addresses. In test runs, `testEndpoint` sends both
/// to the fixture server, which tells engines apart by their `engine` parameter.
struct WebSearch {
    let engine: SearchEngine
    let testEndpoint: URL?

    func searchURL(for query: String) -> URL? {
        testEndpoint.map { fixture("search.html", query: query, at: $0) } ?? engine.searchURL(for: query)
    }

    func suggestionsURL(for query: String) -> URL? {
        testEndpoint.map { fixture("suggest.json", query: query, at: $0) } ?? engine.suggestionsURL(for: query)
    }

    private func fixture(_ name: String, query: String, at endpoint: URL) -> URL {
        endpoint.appending(path: name).appending(queryItems: [
            URLQueryItem(name: "engine", value: engine.rawValue), URLQueryItem(name: "q", value: query)
        ])
    }
}

/// Fetches search suggestions away from the main actor, through the anonymous session.
/// Suggestions are best effort: a slow, failing or malformed answer only leaves them out.
struct SuggestionFetcher: Sendable {
    private static let timeout: TimeInterval = 3
    private static let maximumBytes = 64 * 1024

    private let session = URLSession.anonymous(requestTimeout: timeout, resourceTimeout: timeout)

    /// Cancelling the calling task cancels the request.
    @concurrent
    func suggestions(from url: URL, for query: String) async -> [String] {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= Self.maximumBytes else { return [] }
        return SearchSuggestions.parse(data, query: query)
    }
}
