import AppKit
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
