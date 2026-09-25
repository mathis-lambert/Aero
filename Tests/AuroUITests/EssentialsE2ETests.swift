import XCTest

/// Find in page, downloads and tab reordering. See docs/BROWSING.md.
@MainActor
final class EssentialsE2ETests: BrowserE2ETestCase {
    private static let dragHold: TimeInterval = 0.6

    func testFindInPageSelectsMatchesAndReportsMisses() {
        open("find.html", expecting: "Nothing selected")
        app.typeKey("f", modifierFlags: .command)
        let field = app.textFields["find.input"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.renderTimeout))
        field.typeText("needle")
        XCTAssertTrue(app.webViews.staticTexts["Selected needle"].waitForExistence(timeout: Self.renderTimeout),
                      "The first match is selected in the page")
        XCTAssertFalse(app.staticTexts["find.noMatches"].exists)
        attachScreenshot("find-match")

        field.typeText("zzz")
        XCTAssertTrue(app.staticTexts["find.noMatches"].waitForExistence(timeout: Self.renderTimeout), "A miss is reported")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.waitForExistence(timeout: 1), "Escape closes the bar")
    }

    func testDownloadCompletesAndCanBeCleared() {
        open("downloads.html", expecting: "Download report")
        app.webViews.links["Download report"].click()
        let row = app.descendants(matching: .any).matching(identifier: "downloads.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.pageTimeout), "The download appears in the sidebar")
        XCTAssertTrue(app.staticTexts["report.csv"].exists)
        XCTAssertTrue(app.buttons["downloads.reveal"].waitForExistence(timeout: Self.pageTimeout), "The download finishes")
        XCTAssertFalse(app.staticTexts["This page could not be opened"].exists, "The page that started the download stays displayed")
        attachScreenshot("download-finished")

        app.buttons["downloads.clear"].click()
        XCTAssertFalse(row.waitForExistence(timeout: 1), "Clearing finished downloads hides the section")
    }

    func testTabsReorderAndPinByDragging() {
        open("solid.html", expecting: "Solid fixture")
        open("favicon.html", expecting: "Favicon fixture")
        open("keys.html", expecting: "No shortcut yet")
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture", "Favicon fixture", "Keys fixture"])

        drag(element(tabRows, "Keys fixture"), onto: element(tabRows, "Favicon fixture"))
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Solid fixture", "Keys fixture", "Favicon fixture"] },
                      "Dropping on a row inserts before it")

        element(tabRows, "Solid fixture").rightClick()
        app.menuItems["Pin tab"].click()
        let pinned = app.buttons.matching(identifier: "sidebar.pinned")
        XCTAssertTrue(poll { self.labels(of: "sidebar.pinned") == ["Solid fixture"] })

        drag(element(tabRows, "Keys fixture"), onto: element(pinned, "Solid fixture"))
        XCTAssertTrue(poll { self.labels(of: "sidebar.pinned") == ["Keys fixture", "Solid fixture"] }, "Dropping on the pinned grid pins")
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Favicon fixture"])

        drag(element(pinned, "Keys fixture"), onto: element(tabRows, "Favicon fixture"))
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Keys fixture", "Favicon fixture"] }, "Dropping on the list unpins")
        XCTAssertEqual(labels(of: "sidebar.pinned"), ["Solid fixture"])
        attachScreenshot("tabs-reordered")
    }

    private func element(_ query: XCUIElementQuery, _ label: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func drag(_ source: XCUIElement, onto target: XCUIElement) {
        source.click(forDuration: Self.dragHold, thenDragTo: target)
    }
}
