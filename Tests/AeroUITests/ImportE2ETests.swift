import XCTest

/// docs/ONBOARDING.md › When it appears and failure mode 2: someone already using Aero imports from the File menu,
/// and importing again adds nothing twice.
@MainActor
final class ImportE2ETests: BrowserE2ETestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        server = try FixtureServer()
        app = TestApplication.make()
        app.launchEnvironment["AERO_TEST_IMPORT_SOURCES"] = Self.fixtures.appendingPathComponent("import-sources").path
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout), "no onboarding without the opt-in")
    }

    private func importChrome(_ name: String) {
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Import from Another Browser…"].click()
        let chrome = app.buttons["onboarding.source.Google Chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: Self.renderTimeout), "the import steps open")
        chrome.click()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { next.isEnabled })
        next.click()
        next.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Everything is here." })
        attachScreenshot(name)
        next.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "Done closes the import")
    }

    func testImportingTwiceAddsNothingTwice() {
        importChrome("first import")
        let spaces = labels(of: "sidebar.space")
        let favorites = labels(of: "sidebar.favorite") + labels(of: "sidebar.tile")
        let groups = labels(of: "sidebar.group")
        XCTAssertFalse(favorites.isEmpty, "Chrome's bookmarks bar is in the sidebar")
        importChrome("second import")
        XCTAssertEqual(labels(of: "sidebar.space"), spaces, "no space added twice")
        XCTAssertEqual(labels(of: "sidebar.group"), groups, "no group added twice, even two with the same name")
        XCTAssertEqual(labels(of: "sidebar.favorite") + labels(of: "sidebar.tile"), favorites, "no favorite added twice")
        attachScreenshot("after the second import")
    }

    /// Escape cancels the import for someone already browsing.
    func testEscapeCancelsTheImport() {
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Import from Another Browser…"].click()
        XCTAssertTrue(app.buttons["onboarding.source.Google Chrome"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists })
    }
}
