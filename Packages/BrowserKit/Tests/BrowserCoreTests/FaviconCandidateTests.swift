import Foundation
import Testing
@testable import BrowserCore

// Failure modes 1 and 2 in docs/BROWSING.md › Favicons.

private let page = URL(string: "https://example.com/articles/1")!
private let target = FaviconCandidate.targetPixelSize

private func link(_ href: String, rel: String = "icon", sizes: String? = nil, type: String? = nil) -> FaviconLink {
    FaviconLink(rel: rel, href: href, sizes: sizes, type: type)
}

private func urls(_ links: [FaviconLink]) -> [String] {
    FaviconCandidate.ranked(from: links, pageURL: page).map(\.url.absoluteString)
}

@Test func sufficientlyLargeIconsWinOverTinyOnes() {
    #expect(urls([
        link("https://example.com/16.png", sizes: "16x16"),
        link("https://example.com/touch.png", rel: "apple-touch-icon"),
        link("https://example.com/256.png", sizes: "256x256"),
        link("https://example.com/64.png", sizes: "\(target)x\(target)")
    ]) == [
        "https://example.com/64.png",
        "https://example.com/touch.png",
        "https://example.com/256.png",
        "https://example.com/16.png",
        "https://example.com/favicon.ico"
    ])
}

@Test func unknownAndMultipleSizesAreParsedDefensively() {
    #expect(urls([
        link("https://example.com/any.png", sizes: "any"),
        link("https://example.com/garbage.png", sizes: "x × 12qq"),
        link("https://example.com/multi.ico", sizes: "16x16 128X128")
    ]) == [
        "https://example.com/multi.ico",
        "https://example.com/any.png",
        "https://example.com/garbage.png",
        "https://example.com/favicon.ico"
    ])
}

@Test func unusableDeclarationsAreRejected() {
    #expect(urls([
        link("javascript:alert(1)"),
        link("data:image/png;base64,AAAA"),
        link("https://example.com/vector.svg", type: "image/svg+xml"),
        link("https://example.com/vector.svg"),
        link("https://example.com/mask.png", rel: "mask-icon"),
        link("https://example.com/manifest.json", rel: "manifest"),
        link(String(repeating: "a", count: FaviconCandidate.maximumURLLength + 1))
    ]) == ["https://example.com/favicon.ico"])
}

@Test func fallbackIsAddedOnceAndCandidatesAreBounded() {
    let many = (0..<50).map { link("https://example.com/\($0).png", sizes: "\(target)x\(target)") }
    let ranked = FaviconCandidate.ranked(from: many + [link("https://example.com/favicon.ico")], pageURL: page)
    #expect(ranked.count == FaviconCandidate.maximumCandidates)
    #expect(urls([link("https://example.com/favicon.ico")]) == ["https://example.com/favicon.ico"])
}

@Test func pagesWithoutAWebOriginHaveNoCandidates() {
    #expect(FaviconCandidate.ranked(from: [link("https://example.com/a.png")], pageURL: URL(string: "about:blank")!).isEmpty)
}
