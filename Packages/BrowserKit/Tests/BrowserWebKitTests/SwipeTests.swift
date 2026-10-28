import AppKit
import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// docs/BROWSING.md › Swiping through history. Written as failure modes first:
// 1. Fingers moving right do not go back, or going back needs no threshold.
// 2. A vertical scroll, a mouse wheel or the momentum after the fingers left swipes.
// 3. Content that can still scroll sideways under the fingers loses its scroll to the history.
// 4. Held past the threshold, no list opens, the fingers do not turn it the way content scrolls, the page under it
//    scrolls too, lifting them does not go to the page picked, or there is no way back out.
// Needs access to macOS WebKit services.

@MainActor
@Test func fingersMovingRightGoBackPastTheThreshold() async throws {
    let (page, server) = try await pageWithHistory()
    defer { withExtendedLifetime(server) {} }
    let sign: CGFloat = try #require(scroll(.began)).isDirectionInvertedFromDevice ? 1 : -1
    try await swipe(page, fingers: 60, sign: sign)
    #expect(page.swipe?.direction == .back && page.swipe?.phase == .tracking, "Short of the threshold, it only shows")
    page.track(try #require(scroll(.ended)))
    #expect(page.swipe == nil && page.webView.title == "Second", "Let go short: nothing happens")

    try await swipe(page, fingers: 200, sign: sign)
    #expect(page.swipe?.phase == .ready)
    page.track(try #require(scroll(.ended)))
    try await until { page.webView.title == "First" }
    #expect(page.swipe == nil)
    page.dispose()
}

@MainActor
@Test func onlyAHorizontalSwipeOfTheFingersSwipes() async throws {
    let (page, server) = try await pageWithHistory()
    defer { withExtendedLifetime(server) {} }
    let sign: CGFloat = try #require(scroll(.began)).isDirectionInvertedFromDevice ? 1 : -1
    page.track(try #require(scroll(.began)))
    for _ in 0..<10 { page.track(try #require(scroll(.changed, dx: 4 * sign, dy: 30 * sign))) }
    #expect(page.swipe == nil, "Vertical: the page scrolls")
    page.track(try #require(scroll(.ended)))

    let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 20, wheel3: 0))
    page.track(try #require(NSEvent(cgEvent: wheel)))
    #expect(page.swipe == nil, "A mouse wheel never swipes")
    page.dispose()
}

@MainActor
@Test func contentThatCanScrollSidewaysKeepsTheFingers() async throws {
    let (page, server) = try await pageWithHistory(strip: true)
    defer { withExtendedLifetime(server) {} }
    try await until { (try? await page.webView.callAsyncJavaScript("return document.getElementById('strip').scrollLeft", contentWorld: .page) as? Double) == 200 }
    let sign: CGFloat = try #require(scroll(.began)).isDirectionInvertedFromDevice ? 1 : -1
    try await swipe(page, fingers: 200, sign: sign)
    try await Task.sleep(for: .milliseconds(300))
    page.track(try #require(scroll(.changed, dx: 10 * sign)))
    #expect(page.swipe == nil, "The strip scrolls back; the history waits")
    page.dispose()
}

@MainActor
@Test func heldPastTheThresholdTheFingersTurnTheListAndGoWhereTheyLeaveIt() async throws {
    let (page, server) = try await pageWithHistory(third: true)
    defer { withExtendedLifetime(server) {} }
    let sign: CGFloat = try #require(scroll(.began)).isDirectionInvertedFromDevice ? 1 : -1
    try await swipe(page, fingers: 200, sign: sign)
    try await until { if case .listing = page.swipe?.phase { true } else { false } }
    #expect(page.history(.back).map(\.title) == ["Second", "First"], "Most recent first")
    #expect(page.track(try #require(scroll(.changed, dy: 30 * sign))), "The page under the list never scrolls")
    #expect(page.swipe?.phase == .listing(picked: 0), "Down: nothing nearer than the nearest")
    #expect((page.swipe?.drift.height ?? 0) < 0, "The list stretches past its end")
    page.track(try #require(scroll(.changed, dy: -60 * sign)))
    #expect(page.swipe?.phase == .listing(picked: 1), "Up brings the older pages under the arrow")
    page.track(try #require(scroll(.ended)))
    try await until { page.webView.title == "First" }
    #expect(page.swipe == nil, "Lifting the fingers went to the page picked")

    page.webView.goForward()
    try await until { page.webView.title == "Second" }
    try await swipe(page, fingers: 200, sign: sign)
    try await until { if case .listing = page.swipe?.phase { true } else { false } }
    for _ in 0..<15 { page.track(try #require(scroll(.changed, dx: -10 * sign))) }
    #expect(page.swipe == nil, "Back toward its edge, the list closes")
    page.track(try #require(scroll(.ended)))
    try await Task.sleep(for: .milliseconds(200))
    #expect(page.webView.title == "Second", "And nothing happens")
    page.dispose()
}

// MARK: - Helpers

/// A trackpad scroll event of the given phase, `dx` and `dy` in points.
private func scroll(_ phase: CGScrollPhase, dx: CGFloat = 0, dy: CGFloat = 0) -> NSEvent? {
    guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return nil }
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
    event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
    event.location = CGPoint(x: 200, y: 200)
    return NSEvent(cgEvent: event)
}

/// Fingers going down and moving right by `fingers` points, in steps; once the swipe turns out horizontal, the page
/// answers whether it can scroll there before the fingers go on, as it does between a trackpad's events.
@MainActor
private func swipe(_ page: BrowserPage, fingers: CGFloat, sign: CGFloat) async throws {
    guard let began = scroll(.began) else { return }
    page.track(began)
    // A web view outside a window has no place on screen for an event's location: the fingers go down in the page.
    page.swipeTracking = SwipeTracking(point: CGPoint(x: 100, y: 100))
    var moved: CGFloat = 0
    while moved < fingers {
        if let event = scroll(.changed, dx: 10 * sign) { page.track(event) }
        moved += 10
        if moved == 10 { try await until { page.swipeTracking?.room != nil || page.swipeTracking?.horizontal == false } }
    }
}

/// A page at "Second", with "First" back; with `third`, at "Third" with both back. Pages served on loopback, as
/// pages loaded from strings leave no history; `strip` gives the second page content scrolled sideways.
@MainActor
private func pageWithHistory(strip: Bool = false, third: Bool = false) async throws -> (BrowserPage, HistoryPageServer) {
    let server = try HistoryPageServer(response: """
        HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n
        <style>body { margin: 0 } #strip { overflow-x: auto; width: 100vw; height: 100vh } #strip div { width: 400vw; height: 100% }</style>
        <script>
        document.title = { "/first": "First", "/second": "Second", "/strip": "Second", "/third": "Third" }[location.pathname];
        if (location.pathname === "/strip") addEventListener("DOMContentLoaded", () => {
            document.body.innerHTML = '<div id="strip"><div></div></div>';
            document.getElementById("strip").scrollLeft = 200;
        });
        </script>
        """)
    let page = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    page.webView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let paths = ["first", strip ? "strip" : "second"] + (third ? ["third"] : [])
    for path in paths {
        page.load(server.url.appendingPathComponent(path))
        try await until { page.webView.url?.lastPathComponent == path && !page.webView.isLoading && !(page.webView.title ?? "").isEmpty }
    }
    return (page, server)
}

@MainActor
private func until(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while await !condition() {
        guard ContinuousClock.now < deadline else { Issue.record("Timed out"); throw CancellationError() }
        try await Task.sleep(for: .milliseconds(20))
    }
}
