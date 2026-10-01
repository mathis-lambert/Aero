import AppKit
import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// WebKit's own popover for an action: its page reaches the worker and has no tab of its own, WebKit sizes it to the page
// within Chrome's bounds,
// a native `action.setPopup` changes the next popup, the page can open a tab, and closing or unloading releases it.
@MainActor
@Test func actionPopupKeepsItsWorkerAndBoundsAsContentGrows() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-popup-\(UUID().uuidString)")
    let source = folder.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(#"{"manifest_version":3,"name":"Popup fixture","version":"1","action":{"default_popup":"popup.html"},"background":{"service_worker":"worker.js"}}"#.utf8)
        .write(to: source.appendingPathComponent("manifest.json"))
    try Data("browser.runtime.onMessage.addListener(message => Promise.resolve({echo:message.echo}));".utf8)
        .write(to: source.appendingPathComponent("worker.js"))
    try Data("<html><body><script src='popup.js'></script></body></html>".utf8).write(to: source.appendingPathComponent("popup.html"))
    try Data("<html><body>Connection example</body></html>".utf8).write(to: source.appendingPathComponent("connection.html"))
    try Data("""
        (async () => {
            const reply = await browser.runtime.sendMessage({echo: 'worker replied'});
            document.body.textContent = reply.echo;
            document.body.style.width = '1200px';
            document.body.style.height = '900px';
        })();
        """.utf8).write(to: source.appendingPathComponent("popup.js"))
    let host = TestHost()
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    host.mainWindow = window
    window.orderFront(nil)
    defer { window.close() }
    let registry = ExtensionRegistry(folder: folder.appendingPathComponent("packages"), nativeHostFolders: [], ephemeral: true) { _ in .nonPersistent() }
    registry.host = host
    let owner = registry.extensions(for: UUID())
    let candidate = try await owner.prepare(folder: source)
    var record = InstalledExtension(id: candidate.identifier, version: "1", source: .folder(source), grantedPermissions: [], grantedSites: [])
    record.packageID = candidate.packageID
    host.records = [record]
    try await owner.load(record)
    defer { try? owner.unload(record.id) }

    let selected = BrowserTab(spaceID: UUID(), url: URL(string: "https://example.com/")!)
    host.browserTabs = [selected]
    host.selectedTabID = selected.id
    owner.didOpenTab(selected.id)
    owner.didActivateTab(selected.id, previous: nil)
    owner.performAction(for: record.id)
    let actionDeadline = ContinuousClock.now + .seconds(15)
    while owner.popups[record.id] == nil, ContinuousClock.now < actionDeadline { try await Task.sleep(for: .milliseconds(20)) }
    let popup = try #require(owner.popups[record.id])
    let page = try #require(popup.action.popupWebView)
    let deadline = ContinuousClock.now + .seconds(10)
    var replied = false
    while !replied, ContinuousClock.now < deadline {
        if !page.isLoading {
            replied = try await page.callAsyncJavaScript("return document.body.textContent === 'worker replied';", contentWorld: .page) as? Bool == true
        }
        if !replied { try await Task.sleep(for: .milliseconds(50)) }
    }
    #expect(replied)
    let current = try await page.callAsyncJavaScript("return (await chrome.tabs.getCurrent()) === undefined;", contentWorld: .page) as? Bool
    #expect(current == true, "A popup has no tab, as in Chrome, even with a tab selected")
    let sizeDeadline = ContinuousClock.now + .seconds(5)
    while popup.popover.contentSize.width < 790, ContinuousClock.now < sizeDeadline { try await Task.sleep(for: .milliseconds(50)) }
    #expect(popup.popover.contentSize.width > 700, "WebKit sizes the popup to its page")
    #expect(popup.popover.contentSize.width <= 800, "WebKit keeps the popup within Chrome's width")
    #expect(popup.popover.contentSize.height <= 600, "WebKit keeps the popup within Chrome's height")

    _ = try await page.callAsyncJavaScript("await chrome.action.setPopup({popup: 'connection.html'}); return true;", contentWorld: .page)
    owner.closePopup(of: record.id)
    owner.performAction(for: record.id)
    let reopenDeadline = ContinuousClock.now + .seconds(15)
    while owner.popups[record.id] == nil, ContinuousClock.now < reopenDeadline { try await Task.sleep(for: .milliseconds(20)) }
    let connection = try #require(owner.popups[record.id]?.action.popupWebView)
    let connectionDeadline = ContinuousClock.now + .seconds(10)
    while connection.isLoading || connection.url?.path != "/connection.html", ContinuousClock.now < connectionDeadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(connection.url?.path == "/connection.html")
    let opened = try await connection.callAsyncJavaScript("""
        const tab = await chrome.tabs.create({url: 'https://example.com/connection', active: true});
        return typeof tab.id === 'number';
        """, contentWorld: .page) as? Bool
    #expect(opened == true)
    #expect(host.openedURLs.last?.absoluteString == "https://example.com/connection")
    #expect(host.selectedTabID == host.browserTabs.last?.id)
    try owner.unload(record.id)
    #expect(owner.popups[record.id] == nil)
}
