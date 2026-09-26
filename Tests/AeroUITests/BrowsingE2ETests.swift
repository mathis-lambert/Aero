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

    func testSiteDataClearsAndPermissionsPersist() {
        open("site.html", host: "127.0.0.1", expecting: "No cookie")
        setCookie()
        open("site.html", expecting: "No cookie")
        setCookie()

        siteMenu("Clear cookies")
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "Clearing cookies reloads the page without them")
        setCookie()
        siteMenu("Site settings…")
        let cookies = app.staticTexts["siteSettings.cookies"]
        XCTAssertTrue(cookies.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(poll { cookies.value as? String == "1 cookie" }, "The popover counts the site's cookies")
        attachScreenshot("site-settings")
        app.buttons["siteSettings.deleteData"].click()
        XCTAssertTrue(poll { cookies.value as? String == "No cookies" })
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "Deleting data reloads the page")

        choose("Block", for: "siteSettings.camera")
        choose("Block", for: "siteSettings.location")
        app.typeKey(.escape, modifierFlags: [])
        app.webViews.buttons["Use camera"].click()
        XCTAssertTrue(page("Camera NotAllowedError").waitForExistence(timeout: Self.pageTimeout), "A blocked camera is refused without a prompt")
        app.webViews.buttons["Use location"].click()
        XCTAssertTrue(page("Location denied").waitForExistence(timeout: Self.pageTimeout), "A blocked location is refused without a prompt")

        tabRows.element(boundBy: 0).click()
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.pageTimeout), "Another site keeps its cookies")

        quitAndRelaunch()
        tabRows.element(boundBy: 1).click()
        siteMenu("Site settings…")
        XCTAssertTrue(app.popUpButtons["siteSettings.camera"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(app.popUpButtons["siteSettings.camera"].value as? String, "Block", "Decisions survive a relaunch")
        XCTAssertEqual(app.popUpButtons["siteSettings.microphone"].value as? String, "Ask")
    }

    private func page(_ text: String) -> XCUIElement { app.webViews.staticTexts[text] }

    private func setCookie() {
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.renderTimeout))
    }

    private func siteMenu(_ item: String) {
        app.buttons["sidebar.reload"].rightClick()
        app.menuItems[item].click()
    }

    private func choose(_ decision: String, for permission: String) {
        app.popUpButtons[permission].click()
        app.menuItems[decision].click()
        XCTAssertTrue(poll { self.app.popUpButtons[permission].value as? String == decision })
    }

    private func waitForTabIcon(_ color: ScreenshotColor) -> Bool {
        let row = tabRows.firstMatch
        guard row.waitForExistence(timeout: Self.pageTimeout) else { return false }
        return poll { color.isShown(in: row, at: CGPoint(x: Self.tabIconCenterX, y: row.frame.height / 2)) }
    }
}
