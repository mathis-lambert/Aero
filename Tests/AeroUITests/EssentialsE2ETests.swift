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
        app.buttons["downloads.button"].click()
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout), "The popover says there are none yet")
        app.typeKey(.escape, modifierFlags: [])
        app.webViews.links["Download report"].click()
        app.buttons["downloads.button"].click()
        let row = app.descendants(matching: .any).matching(identifier: "downloads.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.pageTimeout), "The download appears in the popover")
        XCTAssertTrue(app.staticTexts["report.csv"].exists)
        XCTAssertTrue(app.buttons["downloads.reveal"].waitForExistence(timeout: Self.pageTimeout), "The download finishes")
        XCTAssertFalse(app.staticTexts["This page could not be opened"].exists, "The page that started the download stays displayed")
        attachScreenshot("download-finished")

        app.buttons["downloads.clear"].click()
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout), "Clearing removes finished downloads")
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["downloads.button"].click()
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout), "The popover reopens with the current list")
    }

    func testTabsMoveByDraggingAndFavoritesStayWhenClosed() {
        open("solid.html", expecting: "Solid fixture")
        open("favicon.html", expecting: "Favicon fixture")
        open("keys.html", expecting: "No shortcut yet")
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture", "Favicon fixture", "Keys fixture"])

        drag(element(tabRows, "Keys fixture"), to: element(tabRows, "Favicon fixture"), at: Self.upperHalf)
        attachScreenshot("ordinary-row-drop")
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Solid fixture", "Keys fixture", "Favicon fixture"] },
                      "Rows: \(labels(of: "sidebar.tab")); pinned: \(labels(of: "sidebar.favorite")); grid: \(labels(of: "sidebar.tile"))")

        element(tabRows, "Solid fixture").rightClick()
        app.menuItems["Add to Favorites"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Solid fixture"] }, "Grid: \(labels(of: "sidebar.tile"))")

        drag(element(tabRows, "Keys fixture"), to: element(tiles, "Solid fixture"), at: Self.leadingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Keys fixture", "Solid fixture"] }, "The tiles part before the one dropped on")
        drag(element(tabRows, "Favicon fixture"), to: element(tiles, "Solid fixture"), at: Self.trailingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Keys fixture", "Solid fixture", "Favicon fixture"] }, "…or after it")
        XCTAssertEqual(labels(of: "sidebar.tab"), [])
        attachScreenshot("favorites-grid")

        element(tiles, "Keys fixture").click()
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.pageTimeout))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(poll { !self.page("No shortcut yet").exists }, "Closing a favorite unloads its page")
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Keys fixture", "Solid fixture", "Favicon fixture"], "…and keeps it")
        element(tiles, "Keys fixture").click()
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.pageTimeout), "The favorite loads again")

        drag(element(tiles, "Solid fixture"), to: app.buttons["sidebar.newTab"], at: Self.lowerHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Solid fixture"] }, "A favorite dragged to the open tabs leaves the favorites")
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Keys fixture", "Favicon fixture"])
        attachScreenshot("tabs-moved")

        drag(element(tabRows, "Solid fixture"), to: element(tiles, "Favicon fixture"), at: Self.trailingHalf)
        open("find.html", expecting: "Nothing selected")
        drag(element(tabRows, "Find fixture"), to: element(tiles, "Solid fixture"), at: Self.trailingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Keys fixture", "Favicon fixture", "Solid fixture", "Find fixture"] }, "Actual grid: \(labels(of: "sidebar.tile"))")
        drag(element(tiles, "Find fixture"), to: element(tiles, "Keys fixture"), at: Self.leadingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Find fixture", "Keys fixture", "Favicon fixture", "Solid fixture"] }, "Grid reordering works across rows")
        attachScreenshot("favorites-grid-two-rows")

        drag(element(tiles, "Solid fixture"), to: app.buttons["downloads.button"], at: Self.upperHalf)
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Find fixture", "Keys fixture", "Favicon fixture", "Solid fixture"], "Dropping outside the tab sections leaves order unchanged")
    }

    func testEmptyGridAndPinnedRowCloseThenRemove() {
        open("solid.html", expecting: "Solid fixture")
        let emptyGrid = app.descendants(matching: .any).matching(identifier: "sidebar.emptyGrid").firstMatch
        XCTAssertFalse(emptyGrid.exists, "The empty grid is hidden while idle")
        // The target appears only after pickup. Its top is the sidebar's tab area above the separator.
        let source = element(tabRows, "Solid fixture")
        let separator = app.descendants(matching: .any).matching(identifier: "sidebar.pinnedDropZone").firstMatch
        let target = separator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 12))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: Self.dragHold, thenDragTo: target)
        pause(0.5)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Solid fixture"] }, "Grid: \(labels(of: "sidebar.tile"))")
        XCTAssertFalse(emptyGrid.exists)

        let pinnedZone = app.descendants(matching: .any).matching(identifier: "sidebar.pinnedDropZone").firstMatch
        drag(element(tiles, "Solid fixture"), to: pinnedZone, at: Self.upperHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture"] })
        XCTAssertTrue(poll { !emptyGrid.exists }, "The drop target disappears after dropping outside the grid")
        app.buttons["sidebar.closeTab"].click()
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture"])
        element(favoriteRows, "Solid fixture").hover()
        XCTAssertTrue(app.buttons["sidebar.removeFavorite"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("closed-pinned-favorite")

        element(favoriteRows, "Solid fixture").click()
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertTrue(app.buttons["sidebar.closeTab"].exists)
        app.typeKey("w", modifierFlags: .command)
        element(favoriteRows, "Solid fixture").hover()
        XCTAssertTrue(app.buttons["sidebar.removeFavorite"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["sidebar.removeFavorite"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite").isEmpty })
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.favorite"), [])
        XCTAssertEqual(labels(of: "sidebar.tile"), [])
    }

    func testGroupsRenameAndDuplicateSurviveRelaunch() {
        open("solid.html", expecting: "Solid fixture")
        open("keys.html", expecting: "No shortcut yet")

        element(tabRows, "Solid fixture").rightClick()
        app.menuItems["New Group with Tab"].click()
        let rename = app.textFields["sidebar.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: Self.renderTimeout), "A new group asks for its name")
        typeName("Work\n", into: rename)
        XCTAssertTrue(poll { self.labels(of: "sidebar.group") == ["Work"] })
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture"])

        element(tabRows, "Keys fixture").rightClick()
        chooseInSubmenu("Move to Group", "Work")
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture", "Keys fixture"] })
        XCTAssertEqual(labels(of: "sidebar.tab"), [])

        element(app.buttons.matching(identifier: "sidebar.group"), "Work").click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite").isEmpty }, "The header closes the group")
        element(app.buttons.matching(identifier: "sidebar.group"), "Work").click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite").count == 2 })

        element(favoriteRows, "Keys fixture").rightClick()
        app.menuItems["Rename…"].click()
        typeName("Discarded", into: rename)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture", "Keys fixture"] }, "Escape keeps the name")
        element(favoriteRows, "Keys fixture").rightClick()
        app.menuItems["Rename…"].click()
        typeName("Shortcuts\n", into: rename)
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture", "Shortcuts"] })
        element(favoriteRows, "Shortcuts").click()
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture", "Shortcuts"], "The page's title does not replace the name")

        element(favoriteRows, "Shortcuts").rightClick()
        app.menuItems["Duplicate"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Shortcuts"] }, "The duplicate is an open tab")
        attachScreenshot("group")

        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.group"), ["Work"])
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture", "Shortcuts"])
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Shortcuts"])

        element(app.buttons.matching(identifier: "sidebar.group"), "Work").rightClick()
        app.menuItems["Ungroup"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.group").isEmpty })
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture", "Shortcuts"], "Ungrouping keeps the favorites")
    }

    func testNewTabIsOnePermanentSelectableRow() {
        let newTab = app.buttons["sidebar.newTab"]
        XCTAssertEqual(app.buttons.matching(identifier: "sidebar.newTab").count, 1)
        XCTAssertTrue(newTab.isSelected)
        XCTAssertEqual(labels(of: "sidebar.tab"), [])
        open("solid.html", expecting: "Solid fixture")
        XCTAssertFalse(newTab.isSelected)
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture"])
        XCTAssertLessThan(newTab.frame.maxY, element(tabRows, "Solid fixture").frame.minY)
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(poll { newTab.isSelected })
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture"])
        newTab.click()
        XCTAssertTrue(newTab.isSelected)
        XCTAssertEqual(app.buttons.matching(identifier: "sidebar.newTab").count, 1)
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture"])
        attachScreenshot("new-tab-permanent-row")
    }

    func testFavoritesWithExpandedFrenchLabels() {
        open("solid.html", expecting: "Solid fixture")
        element(tabRows, "Solid fixture").rightClick()
        app.menuItems["Add to Favorites"].click()
        open("keys.html", expecting: "No shortcut yet")
        element(tabRows, "Keys fixture").rightClick()
        app.menuItems["Pin as Tab"].click()
        element(favoriteRows, "Keys fixture").rightClick()
        app.menuItems["Rename…"].click()
        let name = "Documents de travail et références pour le projet"
        typeName(name + "\n", into: app.textFields["sidebar.rename"])
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
            + ["-NSDoubleLocalizedStrings", "YES"]
        quitAndRelaunch()
        let favorite = element(favoriteRows, name)
        XCTAssertTrue(favorite.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Solid fixture"])
        favorite.hover()
        XCTAssertTrue(app.buttons["sidebar.removeFavorite"].isHittable)
        attachScreenshot("favorites-expanded-french")
    }

    private func element(_ query: XCUIElementQuery, _ label: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Replaces the name being edited, as in the profile tests.
    private func typeName(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: Self.renderTimeout))
        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText(text)
    }

    private var tiles: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.tile") }
    private var favoriteRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.favorite") }

    /// Drops land by the half of the element under the pointer.
    private static let upperHalf = CGVector(dx: 0.5, dy: 0.25)
    private static let lowerHalf = CGVector(dx: 0.5, dy: 0.75)
    private static let leadingHalf = CGVector(dx: 0.25, dy: 0.5)
    private static let trailingHalf = CGVector(dx: 0.75, dy: 0.5)

    private func drag(_ source: XCUIElement, to target: XCUIElement, at offset: CGVector) {
        // With an empty grid, pickup reveals a 60-point target plus the section spacing.
        // XCTest resolves the destination before pickup; follow the row's resulting position.
        let expansion: CGFloat = tiles.count == 0 ? 64 : 0
        let destination = target.coordinate(withNormalizedOffset: offset).withOffset(CGVector(dx: 0, dy: expansion))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: Self.dragHold, thenDragTo: destination)
        // Accessibility exposes final frames before the sidebar's spring finishes rendering.
        pause(0.5)
    }
}
