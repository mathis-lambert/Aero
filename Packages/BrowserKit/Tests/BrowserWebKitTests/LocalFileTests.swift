import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// Failure modes: a file the person opens does not load, it reads files outside its folder, or a website navigates
// to a file. Needs access to macOS WebKit services.
@MainActor
@Test func filesLoadWhenOpenedAndNeverFromWebsites() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-files-\(UUID())")
    let page = folder.appending(path: "page/index.html")
    try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("<title>Local page</title><p>Local</p>".utf8).write(to: page)
    try Data("secret".utf8).write(to: folder.appending(path: "outside.txt"))

    let browser = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    func settle() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        try await Task.sleep(for: .milliseconds(50))
        while browser.webView.isLoading, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }
    browser.load(page)
    try await settle()
    #expect(browser.webView.title == "Local page")
    let outside = try await browser.webView.callAsyncJavaScript("""
        try { const response = await fetch('../outside.txt'); return await response.text(); } catch { return 'refused'; }
        """, contentWorld: .page) as? String
    #expect(outside == "refused", "A file reads only its own folder")

    browser.webView.loadHTMLString("<a id='link' href='\(page.absoluteString)'>file</a>", baseURL: URL(string: "https://site.example/"))
    try await settle()
    _ = try await browser.webView.callAsyncJavaScript("document.getElementById('link').click(); return true", contentWorld: .page)
    try await settle()
    #expect(browser.webView.url?.isFileURL != true, "A website never navigates to a file")
}
