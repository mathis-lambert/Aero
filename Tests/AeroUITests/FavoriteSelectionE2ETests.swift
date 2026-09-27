import XCTest

@MainActor
final class FavoriteSelectionE2ETests: BrowserE2ETestCase {
    func testFaviconColorsActiveFavoriteAndSurvivesReload() {
        open("favicon.html", expecting: "Favicon fixture")
        let row = tabRows.firstMatch
        let orange = ScreenshotColor(red: 255, green: 90, blue: 0)
        XCTAssertTrue(poll { orange.isShown(in: row, at: CGPoint(x: 19, y: row.frame.height / 2)) })
        row.rightClick()
        app.menuItems["Add to Favorites"].click()
        let tile = app.buttons.matching(identifier: "sidebar.tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: Self.renderTimeout))
        app.webViews.firstMatch.hover()
        XCTAssertTrue(tile.isSelected)
        let border = ScreenshotColor(red: 166, green: 80, blue: 33)
        XCTAssertTrue(poll { border.isShown(in: tile, at: CGPoint(x: tile.frame.width / 2, y: 0.5)) },
                      "The orange favicon supplies the active outline")
        attachScreenshot("favorite-active-light", of: app)

        app.typeKey("t", modifierFlags: .command)
        controlBarInput.hover()
        XCTAssertFalse(tile.isSelected)
        let idle = ScreenshotColor(red: 222, green: 222, blue: 222)
        XCTAssertTrue(poll { idle.isShown(in: tile, at: CGPoint(x: 6, y: tile.frame.height / 2)) })
        attachScreenshot("favorite-inactive-light", of: app)

        quitAndRelaunch()
        tile.click()
        app.webViews.firstMatch.hover()
        XCTAssertTrue(poll { border.isShown(in: tile, at: CGPoint(x: tile.frame.width / 2, y: 0.5)) },
                      "The highlight is rebuilt from the cached favicon")
        app.launchArguments += ["-browser.appearance", "dark"]
        quitAndRelaunch()
        tile.click()
        app.webViews.firstMatch.hover()
        XCTAssertTrue(tile.isSelected)
        attachScreenshot("favorite-active-dark", of: app)
    }
}
