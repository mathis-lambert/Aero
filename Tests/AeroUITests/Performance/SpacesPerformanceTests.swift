import XCTest

/// Loaded-page and record scaling across many spaces, not a claim about physical swipe frame delivery.
/// `Scripts/measure-memory.swift` samples the app and its WebKit processes at each stage. See docs/PERFORMANCE.md.
@MainActor
final class SpacesPerformanceTests: E2ETestCase {
    func testManySpacesKeepLazyPagesAndStableSwitching() throws {
        try launch { seed in
            for index in 0..<12 {
                let space = try seed.addSpace("Space \(index)", profile: "Identity \(index % 3)")
                for tab in 0..<20 { seed.addTab("solid.html", title: "Fixture \(tab)", in: space) }
            }
        }
        XCTAssertEqual(app.webViews.count, 0, "Restored tabs create no page")
        sampleResources("240 records before loading")
        for _ in 0..<12 {
            chooseInMenuBar("Spaces", "Next Space")
            tabRows.firstMatch.click()
            XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        }
        sampleResources("12 pages after loading")
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<13 { chooseInMenuBar("Spaces", "Next Space") }
        }
        sampleResources("after 39 transitions")
        XCTAssertTrue(space("Space 11").isHittable, "The selected space stays visible in an overflowing footer")
        attachScreenshot("many spaces")

        open("video.html", expecting: "Modes inline")
        app.webViews.buttons["Play"].click()
        chooseInMenuBar("Spaces", "Next Space")
        chooseInMenuBar("Spaces", "Next Space")
        sampleResources("background media")
        chooseInMenuBar("Spaces", "Previous Space")
        chooseInMenuBar("Spaces", "Previous Space")
        XCTAssertTrue(page("Modes inline picture-in-picture inline").waitForExistence(timeout: Self.pageTimeout),
                      "The background video stays live across spaces and returns from picture in picture")
    }

    /// Marks a stage for the external sampler, which attributes WebKit's XPC processes to this app: the runner is
    /// sandboxed and does not weaken its entitlements to inspect other processes.
    private func sampleResources(_ stage: String) {
        print("AERO_SPACES_STAGE=\(stage)")
        attachText("\(stage) at \(Date.now)", named: "stage \(stage)")
        pause(8) // Long enough for the sampler's interval.
    }
}
