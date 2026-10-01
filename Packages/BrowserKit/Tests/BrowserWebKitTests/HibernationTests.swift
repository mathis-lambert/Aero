import BrowserCore
import Foundation
import Testing
@testable import BrowserWebKit

private let immediate = HibernationSettings(isEnabled: true, idleLimit: .zero, keepsFavoritesLoaded: false)
private let pollInterval = Duration.milliseconds(20)
private let loadTimeout = Duration.seconds(10)

@MainActor
private func makeRegistry(_ settings: HibernationSettings = immediate) -> WebPageRegistry {
    WebPageRegistry(downloads: makeTestDownloads(), ephemeral: true, hibernation: settings, liveBackgroundPageLimit: 10)
}

@MainActor
private func makeTab() throws -> BrowserTab {
    BrowserTab(spaceID: UUID(), url: try #require(URL(string: "https://example.invalid")))
}

@MainActor @discardableResult
private func activate(_ tab: BrowserTab, in registry: WebPageRegistry) -> BrowserPage {
    registry.activate(tab, profileID: UUID())
}

@MainActor
private func waitUntilLoaded(_ page: BrowserPage) async throws {
    let deadline = ContinuousClock.now + loadTimeout
    while page.webView.isLoading || page.webView.url == nil {
        guard ContinuousClock.now < deadline else { throw CancellationError() }
        try await Task.sleep(for: pollInterval)
    }
}

@Test @MainActor func idleBackgroundPagesHibernateAndRestoreOnActivation() async throws {
    let registry = makeRegistry()
    let first = try makeTab()
    let second = try makeTab()
    let original = activate(first, in: registry)
    activate(second, in: registry)
    await registry.hibernateDuePages()
    #expect(registry.livePages[first.id] == nil)
    #expect(registry.livePages[second.id] != nil)
    let restored = activate(first, in: registry)
    #expect(restored !== original)
    #expect(registry.livePages[first.id] != nil)
}

@Test @MainActor func unsavedInputKeepsAPageAwake() async throws {
    let registry = makeRegistry()
    let page = activate(try makeTab(), in: registry)
    page.webView.loadHTMLString("<textarea></textarea>", baseURL: URL(string: "https://example.invalid"))
    try await waitUntilLoaded(page)
    #expect(await page.hibernationBlocker() == nil)
    // Trusted input cannot be synthesized; record the edit the way the tracker does.
    _ = try await page.webView.callAsyncJavaScript("""
        const field = document.querySelector("textarea");
        field.value = "Draft";
        globalThis.aeroEditedFields.add(field);
        """, contentWorld: PageScripts.world)
    #expect(await page.hibernationBlocker() == .unsavedInput)
}

// Developer mode reaches open pages and those created later; off, Web Inspector is unavailable.
@Test @MainActor func developerModeMakesEveryPageInspectable() throws {
    let registry = makeRegistry()
    let first = activate(try makeTab(), in: registry)
    #expect(!first.webView.isInspectable)
    registry.pagesAreInspectable = true
    #expect(first.webView.isInspectable)
    #expect(activate(try makeTab(), in: registry).webView.isInspectable)
    registry.pagesAreInspectable = false
    #expect(!first.webView.isInspectable)
}

// Failure mode: a hibernated tab comes back without its `sessionStorage`, which a tab keeps while it lives, so a
// page loses what it saved for the session.
@Test @MainActor func hibernationKeepsSessionStorage() async throws {
    let server = try HistoryPageServer(response: "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 30\r\nConnection: close\r\n\r\n<title>Stored</title><p>ok</p>")
    let registry = makeRegistry()
    let tab = BrowserTab(spaceID: UUID(), url: server.url)
    let page = activate(tab, in: registry)
    try await waitUntilLoaded(page)
    _ = try await page.webView.callAsyncJavaScript("sessionStorage.setItem('draft', 'kept'); return true", contentWorld: .page)
    activate(try makeTab(), in: registry)
    await registry.hibernateDuePages()
    #expect(registry.livePages[tab.id] == nil)
    let restored = activate(tab, in: registry)
    try await waitUntilLoaded(restored)
    let deadline = ContinuousClock.now + loadTimeout
    var value: String?
    while value != "kept", ContinuousClock.now < deadline {
        value = try? await restored.webView.callAsyncJavaScript("return sessionStorage.getItem('draft')", contentWorld: .page) as? String
        if value != "kept" { try await Task.sleep(for: pollInterval) }
    }
    #expect(value == "kept")
}
