import BrowserCore
import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// Failure modes: native main-frame provenance is lost, repeated KVO reports duplicate a visit,
// a reload never becomes a visit, or a same-document address change uses the previous transition.
@MainActor
@Test func mainFrameVisitsKeepNativeNavigationTypesAndReferrers() async throws {
    let html = #"<a id="link" href="/next">Next</a><form id="form" action="/posted" method="post"><input name="example" value="fixture"></form>"#
    let server = try HistoryPageServer(response: "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)")
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let page = BrowserPage(configuration: configuration)
    defer { page.dispose() }
    var visits: [HistoryNavigation] = []
    page.onVisit = { visits.append($0) }
    func waitForVisits(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while (visits.count < count || page.webView.isLoading), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(visits.count == count)
    }
    page.load(server.url)
    try await waitForVisits(1)
    #expect(visits.first?.transition == .typed)
    _ = try await page.webView.evaluateJavaScript("document.getElementById('link').click()")
    try await waitForVisits(2)
    #expect(visits.last?.transition == .link && visits.last?.referrer == server.url)
    _ = try await page.webView.evaluateJavaScript("document.getElementById('form').requestSubmit()")
    try await waitForVisits(3)
    #expect(visits.last?.transition == .formSubmit && visits.last?.referrer?.path == "/next")
    page.reload()
    try await waitForVisits(4)
    #expect(visits.last?.transition == .reload)
    _ = try await page.webView.evaluateJavaScript("history.pushState({},'', '/in-document')")
    try await waitForVisits(5)
    #expect(visits.last?.transition == .link && visits.last?.referrer?.path == "/posted")
}
