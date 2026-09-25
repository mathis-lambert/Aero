import XCTest

/// End-to-end browsing behaviors against local fixtures. See docs/BROWSING.md.
@MainActor
final class BrowsingE2ETests: BrowserE2ETestCase {
    private static let fixtureOrange = ScreenshotColor(red: 255, green: 90, blue: 0)
    private static let fixtureBlue = ScreenshotColor(red: 30, green: 64, blue: 255)
    /// Center of the leading icon in a tab row: 10 pt padding plus half of the 18 pt icon frame.
    private static let tabIconCenterX: CGFloat = 19

    func testFaviconAppearsAndPersistsAcrossRelaunch() {
        open("favicon.html", expecting: "Favicon fixture")
        XCTAssertTrue(waitForTabIcon(Self.fixtureOrange), "The declared favicon is shown in the tab row")
        attachScreenshot("favicon-loaded")

        server.stop()
        relaunch()
        XCTAssertTrue(waitForTabIcon(Self.fixtureOrange), "The cached favicon is shown without loading the page")
        attachScreenshot("favicon-restored")
    }

    func testNewPageRevealsItsContent() {
        open("solid.html", expecting: "Solid fixture")
        let page = app.webViews.firstMatch
        let rendered = poll {
            Self.fixtureBlue.isShown(in: page, at: CGPoint(x: page.frame.width / 2, y: page.frame.height / 2))
        }
        attachScreenshot("page-revealed")
        XCTAssertTrue(rendered, "The page becomes visible after its first frame")
    }

    func testPopupTalksToOpenerAndClosesItself() {
        open("popup-opener.html", expecting: "Waiting for popup")
        app.webViews.buttons["Open popup"].click()
        XCTAssertTrue(app.webViews.staticTexts["Popup fixture"].waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 2, "The popup opens as a tab")
        attachScreenshot("popup-opened")

        app.webViews.buttons["Close popup"].click()
        XCTAssertTrue(app.webViews.staticTexts["Opener received message"].waitForExistence(timeout: Self.pageTimeout),
                      "The opener received the popup's message and is selected again")
        XCTAssertEqual(tabRows.count, 1, "window.close() closes the popup tab")
        attachScreenshot("popup-closed")
    }

    func testPageHandlesPageFirstShortcuts() {
        open("keys.html", expecting: "No shortcut yet")
        app.webViews.firstMatch.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.webViews.staticTexts["Page handled ⌘K"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.textFields["controlBar.input"].exists, "The browser does not steal a shortcut the page handled")
    }

    func testPageShortcutsDoNotOverrideReservedCommands() {
        open("solid.html", expecting: "Solid fixture")
        app.webViews.firstMatch.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.textFields["controlBar.input"].waitForExistence(timeout: Self.renderTimeout),
                      "A page-first shortcut the page ignores reaches the browser")
        app.typeKey(.escape, modifierFlags: [])

        open("keys.html", expecting: "No shortcut yet")
        app.webViews.firstMatch.click()
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout), "⌘T stays with the browser")
        XCTAssertEqual(tabRows.count, 2)
    }

    private func waitForTabIcon(_ color: ScreenshotColor) -> Bool {
        let row = tabRows.firstMatch
        guard row.waitForExistence(timeout: Self.pageTimeout) else { return false }
        return poll { color.isShown(in: row, at: CGPoint(x: Self.tabIconCenterX, y: row.frame.height / 2)) }
    }
}
