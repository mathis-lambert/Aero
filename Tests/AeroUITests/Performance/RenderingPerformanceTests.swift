import AppKit
import XCTest

/// Records page callback cadence, not compositor/physical presentation FPS.
@MainActor
final class RenderingPerformanceTests: E2ETestCase {
    func testPageFrameCadenceAndSmoothScroll() throws {
        try launch()
        open("rendering.html", expecting: "Rendering fixture")
        app.webViews.buttons["Scroll down"].click()
        pause(1)
        app.webViews.buttons["Measure frames"].click()
        let report = app.webViews.textViews["Frame report"]
        XCTAssertTrue(poll(timeout: 10) { (report.value as? String)?.contains("medianMs") == true })
        let text = try XCTUnwrap(report.value as? String)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertGreaterThan(try XCTUnwrap(result["samples"] as? Int), 20)
        XCTAssertGreaterThan(try XCTUnwrap(result["scrollY"] as? Double), 500)
        XCTAssertEqual(result["visibility"] as? String, "visible")
        let displays = NSScreen.screens.map { "\($0.localizedName): maximum \($0.maximumFramesPerSecond) Hz, frame \($0.frame)" }.joined(separator: "\n")
        attachText("\(text)\n\(displays)\nWindow: \(app.windows.firstMatch.frame)\nLow power: \(ProcessInfo.processInfo.isLowPowerModeEnabled)", named: "page frame cadence")
    }
}
