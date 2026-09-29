import XCTest

@MainActor
final class FavoritesGridE2ETests: BrowserE2ETestCase {
    func testTileHeightStaysFixedWhileColumnsAdapt() {
        for (fixture, text, title) in [
            ("solid.html", "Solid fixture", "Solid fixture"),
            ("favicon.html", "Favicon fixture", "Favicon fixture"),
            ("keys.html", "No shortcut yet", "Keys fixture"),
            ("find.html", "Nothing selected", "Find fixture")
        ] {
            open(fixture, expecting: text)
            tabRows.matching(NSPredicate(format: "label == %@", title)).firstMatch.rightClick()
            app.windows.menuItems["Add to Favorites"].click()
        }
        let tiles = app.buttons.matching(identifier: "sidebar.tile")
        XCTAssertEqual(tiles.count, 4)
        let first = tiles.element(boundBy: 0).frame
        XCTAssertGreaterThanOrEqual(first.width, first.height)
        XCTAssertLessThan(first.height / first.width, 0.8)
        assertHeight(first.height, in: tiles)
        XCTAssertEqual(tiles.element(boundBy: 2).frame.minY, first.minY, accuracy: 1)
        XCTAssertGreaterThan(tiles.element(boundBy: 3).frame.minY, first.maxY)
        attachScreenshot("favorites-three-columns", of: app)

        let handle = app.descendants(matching: .any).matching(identifier: "sidebar.resize").firstMatch
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 88, dy: 0)))
        XCTAssertTrue(poll { abs(tiles.element(boundBy: 3).frame.minY - tiles.element(boundBy: 0).frame.minY) < 1 })
        assertHeight(first.height, in: tiles)
        XCTAssertGreaterThan(tiles.element(boundBy: 0).frame.width, first.width)
        attachScreenshot("favorites-four-columns", of: app)
        tiles.element(boundBy: 0).hover()
        pause(0.25) // Let the hover fade settle before capturing its color.
        attachScreenshot("favorites-light-hover", of: app)
        app.launchArguments += ["-browser.appearance", "dark"]
        quitAndRelaunch()
        XCTAssertTrue(tiles.element(boundBy: 0).waitForExistence(timeout: Self.renderTimeout))
        controlBarInput.hover()
        pause(0.25)
        attachScreenshot("favorites-dark-idle", of: app)
        tiles.element(boundBy: 0).hover()
        pause(0.25) // Let the hover fade settle before capturing its color.
        attachScreenshot("favorites-dark-hover", of: app)
    }

    private func assertHeight(_ height: CGFloat, in tiles: XCUIElementQuery) {
        for tile in tiles.allElementsBoundByIndex {
            XCTAssertEqual(tile.frame.height, height, accuracy: 1)
        }
    }
}
