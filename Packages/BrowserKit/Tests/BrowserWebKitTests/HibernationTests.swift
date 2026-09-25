import BrowserCore
import Foundation
import Testing
@testable import BrowserWebKit

private let immediate = HibernationSettings(isEnabled: true, idleLimit: .zero, keepsPinnedTabsLoaded: false)
private let pollInterval = Duration.milliseconds(20)
private let loadTimeout = Duration.seconds(10)

@MainActor
private func makeRegistry(_ settings: HibernationSettings = immediate) -> WebPageRegistry {
    WebPageRegistry(ephemeral: true, hibernation: settings, liveBackgroundPageLimit: 10)
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
    #expect(!registry.isLoaded(first.id))
    #expect(registry.isLoaded(second.id))
    let restored = activate(first, in: registry)
    #expect(restored !== original)
    #expect(registry.isLoaded(first.id))
}

@Test @MainActor func pinnedPagesStayLoadedWhenRequested() async throws {
    var settings = immediate
    settings.keepsPinnedTabsLoaded = true
    let registry = makeRegistry(settings)
    let pinned = try makeTab()
    let delegate = PinnedTabs(pinned: [pinned.id])
    registry.delegate = delegate
    activate(pinned, in: registry)
    registry.deactivate()
    await registry.hibernateDuePages()
    #expect(registry.isLoaded(pinned.id))
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
        globalThis.auroEditedFields.add(field);
        """, contentWorld: PageScripts.world)
    #expect(await page.hibernationBlocker() == .unsavedInput)
}

@MainActor
private final class PinnedTabs: WebPageRegistryDelegate {
    let pinned: Set<UUID>
    init(pinned: Set<UUID>) { self.pinned = pinned }
    func isPinned(_ tabID: UUID) -> Bool { pinned.contains(tabID) }
    func page(_ tabID: UUID, didUpdateURL url: URL, title: String) {}
    func page(_ tabID: UUID, didDeclareIcons links: [FaviconLink], at url: URL) {}
    func page(_ openerTabID: UUID, requestsPopupTabFor url: URL?) -> BrowserTab? { nil }
    func pageDidOpenPopup(_ tabID: UUID) {}
    func pageDidRequestClose(_ tabID: UUID, openerTabID: UUID) {}
}
