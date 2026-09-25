import BrowserCore
import Foundation
import Testing

// docs/CONTROL_BAR.md, failure modes 2 and 3.

private func payload(_ json: String) -> Data { Data(json.utf8) }

@Test func parsesOpenSearchSuggestions() {
    let data = payload(#"["aero", ["aero browser", "aero macos"]]"#)
    #expect(SearchSuggestions.parse(data, query: "aero") == ["aero browser", "aero macos"])
}

@Test func rejectsMalformedSuggestionPayloads() {
    for json in [#"{"q": "aero"}"#, #"["aero"]"#, #"["aero", "aero browser"]"#, "not json", ""] {
        #expect(SearchSuggestions.parse(payload(json), query: "aero").isEmpty, "\(json)")
    }
}

@Test func keepsOnlyUsefulBoundedSuggestions() {
    let long = String(repeating: "a", count: SearchSuggestions.maximumLength + 1)
    let many = (1...50).map { "\"aero \($0)\"" }.joined(separator: ",")
    let data = payload(#"["aero", [1, null, "", "  ", "Aero", "aero x", "aero x", "\#(long)", \#(many)]]"#)
    let result = SearchSuggestions.parse(data, query: "aero")
    #expect(result.first == "aero x", "Non-strings, blanks, the query itself and duplicates are dropped")
    #expect(!result.contains(long))
    #expect(result.count == SearchSuggestions.maximumCount)
}

@Test func enginesEncodeQueries() throws {
    for engine in SearchEngine.allCases {
        let url = try #require(engine.searchURL(for: "été & co"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.value == "été & co" }
        #expect(query != nil, "\(engine) keeps the whole query in one parameter")
        #expect(NavigationInput.isWebURL(url) && url.scheme == "https")
        #expect(engine.suggestionsURL(for: "été & co").map(NavigationInput.isWebURL) == true)
    }
}

@Test func addressesAreRecognizedBeforeSending() {
    for text in ["example.com", "https://example.com/a", "localhost:8080", "127.0.0.1", "aero://history", "javascript:alert(1)", "file:///etc/passwd", "a.b"] {
        #expect(NavigationInput.looksLikeAddress(text), "\(text)")
    }
    for text in ["aero browser", "été à Lyon", "swift", "what is 1 + 1"] {
        #expect(!NavigationInput.looksLikeAddress(text), "\(text)")
    }
}

@Test func onlyOpenableAddressesAreOpened() {
    #expect(NavigationInput.address(from: "example.com/a")?.absoluteString == "https://example.com/a")
    #expect(NavigationInput.address(from: "localhost:8080")?.absoluteString == "http://localhost:8080")
    #expect(NavigationInput.address(from: "aero://history")?.absoluteString == "aero://history")
    for text in ["javascript:alert(1)", "file:///etc/passwd", "été à Lyon", "swift", ""] {
        #expect(NavigationInput.address(from: text) == nil, "\(text) is searched")
    }
}
