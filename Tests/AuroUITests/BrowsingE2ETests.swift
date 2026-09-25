import XCTest

/// End-to-end browsing behaviors against local fixtures. See docs/BROWSING.md.
@MainActor
final class BrowsingE2ETests: XCTestCase {
    private static let pageTimeout: TimeInterval = 10
    private static let renderTimeout: TimeInterval = 5
    private static let pollInterval: TimeInterval = 0.2
    private static let fixtureOrange = ScreenshotColor(red: 255, green: 90, blue: 0)
    private static let fixtureBlue = ScreenshotColor(red: 30, green: 64, blue: 255)
    /// Center of the leading icon in a tab row: 10 pt padding plus half of the 18 pt icon frame.
    private static let tabIconCenterX: CGFloat = 19

    private var app: XCUIApplication!
    private var server: FixtureServer!

    override func setUp() async throws {
        continueAfterFailure = false
        server = try FixtureServer()
        app = TestApplication.make()
        app.launch()
        XCTAssertTrue(newTabInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    override func tearDown() async throws {
        app.terminate()
        server.stop()
    }

    func testFaviconAppearsAndPersistsAcrossRelaunch() {
        open("favicon.html", expecting: "Favicon fixture")
        XCTAssertTrue(waitForTabIcon(Self.fixtureOrange), "The declared favicon is shown in the tab row")
        attachScreenshot("favicon-loaded")

        server.stop()
        app.terminate()
        app.launch()
        XCTAssertTrue(newTabInput.waitForExistence(timeout: TestApplication.launchTimeout))
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
        XCTAssertFalse(app.textFields["command.input"].exists, "The browser does not steal a shortcut the page handled")
    }

    func testPageShortcutsDoNotOverrideReservedCommands() {
        open("solid.html", expecting: "Solid fixture")
        app.webViews.firstMatch.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.textFields["command.input"].waitForExistence(timeout: Self.renderTimeout),
                      "A page-first shortcut the page ignores reaches the browser")
        app.typeKey(.escape, modifierFlags: [])

        open("keys.html", expecting: "No shortcut yet")
        app.webViews.firstMatch.click()
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(newTabInput.waitForExistence(timeout: Self.renderTimeout), "⌘T stays with the browser")
        XCTAssertEqual(tabRows.count, 2)
    }

    // MARK: - Helpers

    private var newTabInput: XCUIElement { app.textFields["newTab.input"] }
    private var tabRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.tab") }

    private func open(_ fixture: String, expecting text: String) {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(newTabInput.waitForExistence(timeout: Self.renderTimeout))
        newTabInput.typeText(server.url(fixture).absoluteString + "\n")
        XCTAssertTrue(app.webViews.staticTexts[text].waitForExistence(timeout: Self.pageTimeout), "\(fixture) loaded")
    }

    private func waitForTabIcon(_ color: ScreenshotColor) -> Bool {
        let row = tabRows.firstMatch
        guard row.waitForExistence(timeout: Self.pageTimeout) else { return false }
        return poll { color.isShown(in: row, at: CGPoint(x: Self.tabIconCenterX, y: row.frame.height / 2)) }
    }

    private func poll(timeout: TimeInterval = renderTimeout, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(Self.pollInterval))
        }
        return condition()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
