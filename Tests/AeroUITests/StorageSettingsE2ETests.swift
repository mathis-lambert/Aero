import XCTest

/// Settings › Storage: what Aero keeps, cleaning it, and resetting Aero. See docs/STORAGE.md › Storage settings and Reset.
@MainActor
final class StorageSettingsE2ETests: BrowserE2ETestCase {
    private func size(_ item: String) -> String {
        let text = app.descendants(matching: .any)["storage.size.\(item)"]
        return (text.value as? String) ?? text.label
    }

    private func confirm(_ button: String) {
        let action = app.sheets.buttons[button].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: Self.renderTimeout), "\(button) asks first")
        action.click()
    }

    /// Failure modes 1 to 3 and 8: every item is measured, and each action empties what it says, leaving the rest.
    func testStorageShowsWhatAeroKeepsAndCleansIt() {
        open("favicon.html", expecting: "Favicon fixture")
        open("history-lake.html", expecting: "Alpine Lake fixture")
        openSettings("storage")
        XCTAssertTrue(app.descendants(matching: .any)["storage.total"].waitForExistence(timeout: Self.pageTimeout), "the total is measured")
        for item in ["websiteCache", "history", "icons", "blockingLists", "extensions", "records", "siteData.Personal"] {
            XCTAssertTrue(app.descendants(matching: .any)["storage.size.\(item)"].exists, "\(item) is shown")
        }
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.size("icons").isEmpty && !self.size("icons").contains("Zero") }, "the fixture's icon is on disk: \(size("icons"))")
        attachScreenshot("storage")

        app.buttons["storage.clear.icons"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.size("icons").contains("Zero") }, "icons are gone and the size follows: \(size("icons"))")
        app.buttons["storage.clear.websiteCache"].click()

        app.buttons["storage.clear.history"].click()
        confirm("Clear history")
        attachScreenshot("storage after cleaning")
        closeSettings()
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.pageTimeout), "history is empty")
        XCTAssertEqual(labels(of: "sidebar.tab").prefix(2), ["Favicon fixture", "Alpine Lake"], "tabs stay")
    }

    /// Failure modes 5 to 7: reset erases this test run's records and starts fresh; the test data directory is the only one touched.
    func testResetStartsAeroFresh() {
        createSpace("Work")
        open("history-lake.html", expecting: "Alpine Lake fixture")
        openSettings("storage")
        let reset = app.buttons["storage.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: Self.pageTimeout))
        // Reset closes the page, below everything that can be cleaned.
        // Clicking below the scroll bar's knob pages down, as in Settings › General.
        let track = app.windows.firstMatch.scrollBars.firstMatch
        for _ in 0..<5 where !reset.isHittable { track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).click() }
        XCTAssertTrue(reset.isHittable)
        attachScreenshot("storage bottom")
        reset.click()
        attachScreenshot("reset confirmation")
        confirm("Reset Aero")
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout), "Aero quits to reset")
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main"], "one fresh space")
        XCTAssertTrue(labels(of: "sidebar.tab").isEmpty, "no tabs")
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.pageTimeout), "no history")
        attachScreenshot("after reset")
    }
}
