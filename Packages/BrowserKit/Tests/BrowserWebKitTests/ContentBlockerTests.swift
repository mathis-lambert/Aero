import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// Turning Aero's blocking off on a page takes off only Aero's lists: an extension's `declarativeNetRequest` rules
// share the page's controller and keep applying. Needs access to macOS WebKit services.
@MainActor
@Test func blockingLeavesOtherRuleListsInPlace() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-blocker-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = try #require(WKContentRuleListStore(url: folder))
    let foreign = try await store.compileContentRuleList(forIdentifier: "extension-rules", encodedContentRuleList: """
        [{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".hidden-by-extension"}}]
        """)
    let blocker = try #require(ContentBlocker(directory: folder.appending(path: "aero")))
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    view.configuration.userContentController.add(try #require(foreign))
    blocker.apply(to: view.configuration.userContentController, enabled: true)
    blocker.apply(to: view.configuration.userContentController, enabled: false)
    view.loadHTMLString("<div class='hidden-by-extension'>Hidden</div>", baseURL: URL(string: "https://example.com/"))
    let deadline = ContinuousClock.now + .seconds(15)
    while view.isLoading || view.url == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    let display = try await view.callAsyncJavaScript("return getComputedStyle(document.querySelector('div')).display", contentWorld: .page) as? String
    #expect(display == "none")
}
