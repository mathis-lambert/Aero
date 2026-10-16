import AppKit
import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// `windows.create`: a popup window takes the size it asks for within Chrome's minimum, or a default, and is centered
// unless placed; a normal window without addresses shows the New Tab page; a private window is refused.
@MainActor
@Test func extensionWindowsFollowChromesSizesAndRequests() async throws {
    let loaded = try await LoadedExtension(manifest: #"{"manifest_version":3,"name":"Window example","version":"1"}"#,
                                           files: ["page.html": "<html><body>Window</body></html>"])
    defer { loaded.close() }
    let page = try await loaded.page("page.html")
    func create(_ options: String) async throws -> Any? {
        try await page.callAsyncJavaScript("""
            try { const window = await chrome.windows.create(\(options)); return window.type; }
            catch (error) { return 'refused'; }
            """, contentWorld: .page)
    }
    #expect(try await create("{type: 'popup', url: 'page.html', width: 100, height: 120}") as? String == "popup")
    #expect(loaded.owner.windows.last?.window.contentLayoutRect.size == ExtensionWindow.minimumSize)
    #expect(try await create("{type: 'popup', url: 'page.html'}") as? String == "popup")
    #expect(loaded.owner.windows.last?.window.contentLayoutRect.size == ExtensionWindow.defaultSize)
    #expect(try await create("{type: 'popup', url: 'page.html', width: 500, height: 400}") as? String == "popup")
    #expect(loaded.owner.windows.last?.window.contentLayoutRect.size == CGSize(width: 500, height: 400))
    for window in loaded.owner.windows { window.close() }
    #expect(try await create("{focused: true}") as? String == "normal")
    #expect(loaded.host.newTabRequests == 1)
    #expect(try await create("{incognito: true}") as? String == "refused")
}

// `chrome_url_overrides.newtab`: WebKit names the extension's page, which Aero opens for a new tab, including one an
// extension creates without an address.
@MainActor
@Test func anExtensionReplacesTheNewTabPage() async throws {
    let loaded = try await LoadedExtension(manifest: #"{"manifest_version":3,"name":"New Tab example","version":"1","chrome_url_overrides":{"newtab":"tab.html"}}"#,
                                           files: ["tab.html": "<html><body>Tab</body></html>", "page.html": "<html><body>Page</body></html>"])
    defer { loaded.close() }
    let page = try #require(URL(string: "chrome-extension://\(loaded.record.id)/tab.html"))
    #expect(loaded.owner.newTabPageURL(order: [loaded.record.id]) == page)
    #expect(loaded.owner.newTabPageURL(order: []) == nil, "A disabled or removed extension replaces nothing")
    loaded.host.records = [loaded.record]
    let view = try await loaded.page("page.html")
    _ = try await view.callAsyncJavaScript("await chrome.tabs.create({}); return true", contentWorld: .page)
    #expect(loaded.host.openedURLs.last == page)
}

// Developer mode reaches a loaded extension's context, so its background and pages can be inspected.
@MainActor
@Test func developerModeMakesExtensionsInspectable() async throws {
    let loaded = try await LoadedExtension(manifest: #"{"manifest_version":3,"name":"Inspectable example","version":"1"}"#)
    defer { loaded.close() }
    let context = try #require(loaded.owner.contexts[loaded.record.id])
    #expect(!context.isInspectable)
    loaded.registry.isInspectable = true
    #expect(context.isInspectable)
}

// WebKit hides every tab of a window without an active one. With none of the profile's tabs selected, as on the New
// Tab page or in another profile's space, the tab last activated stays active, or the first one.
@MainActor
@Test func theMainWindowKeepsAnActiveTabWithoutASelection() async throws {
    let loaded = try await LoadedExtension(manifest: #"{"manifest_version":3,"name":"Tabs example","version":"1"}"#,
                                           files: ["page.html": "<html><body>Tabs</body></html>"])
    defer { loaded.close() }
    let first = BrowserTab(spaceID: UUID(), url: try #require(URL(string: "https://example.com/first")))
    let second = BrowserTab(spaceID: first.spaceID, url: try #require(URL(string: "https://example.com/second")))
    loaded.host.browserTabs = [first, second]
    for tab in [first, second] { loaded.owner.didOpenTab(tab.id) }
    let page = try await loaded.page("page.html")
    func activeIndices() async throws -> [Int] {
        try await page.callAsyncJavaScript("""
            const tabs = await chrome.tabs.query({});
            return tabs.length === \(loaded.host.browserTabs.count) ? tabs.filter(tab => tab.active).map(tab => tab.index) : [];
            """, contentWorld: .page) as? [Int] ?? []
    }
    #expect(try await activeIndices() == [0], "Before any selection, the first tab")
    loaded.host.selectedTabID = second.id
    loaded.owner.didActivateTab(second.id, previous: nil)
    #expect(try await activeIndices() == [1])
    loaded.host.selectedTabID = nil
    #expect(try await activeIndices() == [1], "The New Tab page leaves the last tab active")
    loaded.host.browserTabs = [first]
    loaded.owner.didCloseTab(second.id)
    #expect(try await activeIndices() == [0], "A closed tab is not kept")
}
