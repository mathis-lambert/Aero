import BrowserCore
import Foundation
import Testing
@testable import BrowserWebKit

// docs/BROWSING.md › Peek. Written as failure modes first:
// 1. The page script's answer previews an address that is not a website's, or one beyond bounds.
// 2. The link's frame is reported in CSS pixels instead of the web view's points, so the card grows from elsewhere.
// 3. A tab without a live page opens a preview, with no profile to give it.
// 4. Opening the preview in a tab reloads it, or leaves it outside the tab's lifecycle (hibernation, events).
// Needs access to macOS WebKit services.

@MainActor
private func makeRegistry() -> WebPageRegistry {
    WebPageRegistry(downloads: makeTestDownloads(), ephemeral: true, hibernation: .default, liveBackgroundPageLimit: 10)
}

@Test @MainActor func onlyWebsiteLinksWithinBoundsArePreviewed() {
    let page = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    #expect(page.peekLink(from: ["href": "javascript:alert(1)"]) == nil)
    #expect(page.peekLink(from: ["href": "file:///etc/hosts"]) == nil)
    #expect(page.peekLink(from: ["href": "https://example.com/" + String(repeating: "a", count: PeekScripts.maximumAddressLength)]) == nil)
    #expect(page.peekLink(from: ["href": 42]) == nil)
    #expect(page.peekLink(from: NSNull()) == nil, "No link under the pointer")
    #expect(page.peekLink(from: ["href": "https://example.com/article"])?.url == URL(string: "https://example.com/article"))
}

@Test @MainActor func theLinkFrameIsInTheViewsPoints() {
    let page = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    page.webView.pageZoom = 2
    let link = page.peekLink(from: ["href": "https://example.com", "rect": ["x": 10.0, "y": 20.0, "width": 30.0, "height": 5.0]])
    #expect(link?.origin == CGRect(x: 20, y: 40, width: 60, height: 10))
    let empty = page.peekLink(from: ["href": "https://example.com", "rect": ["x": 10.0, "y": 20.0, "width": 0.0, "height": 5.0]])
    #expect(empty != nil && empty?.origin == nil, "An empty frame gives no place to grow from")
}

@Test @MainActor func aPreviewNeedsALiveOpenerAndBecomesTheTabsPageAsItIs() throws {
    let registry = makeRegistry()
    let url = try #require(URL(string: "https://example.invalid/linked"))
    #expect(registry.makePeekPage(url, from: UUID()) == nil)

    let opener = BrowserTab(spaceID: UUID(), url: try #require(URL(string: "https://example.invalid")))
    let profileID = UUID()
    registry.activate(opener, profileID: profileID)
    let page = try #require(registry.makePeekPage(url, from: opener.id))
    #expect(registry.livePage(opener.id) !== page)

    let tabID = UUID()
    registry.adoptPeekPage(page, as: tabID, profileID: profileID)
    #expect(registry.livePage(tabID) === page, "The tab takes the preview's page instead of loading another")
    #expect(page.onMetadata != nil && page.onPeek != nil, "Once a tab's, the page reports to it and previews links")
}
