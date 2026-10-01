import XCTest

/// Organizing tabs in the sidebar, its menus, and how it follows the window. The order rules themselves are
/// covered by SidebarTabsTests. See docs/BROWSING.md › Favorites and open tabs and docs/SHORTCUTS.md › Menus.
@MainActor
final class SidebarJourneys: E2ETestCase {
    private static let dragHold: TimeInterval = 0.6
    /// Over the target before releasing, so the drop delegate has seen where the drag is.
    private static let dropHold: TimeInterval = 0.3
    /// Drops land by the half of the element under the pointer.
    private static let upperHalf = CGVector(dx: 0.5, dy: 0.25)
    private static let lowerHalf = CGVector(dx: 0.5, dy: 0.75)
    private static let leadingHalf = CGVector(dx: 0.25, dy: 0.5)
    private static let trailingHalf = CGVector(dx: 0.75, dy: 0.5)

    private var pinnedDropZone: XCUIElement { element("sidebar.pinnedDropZone") }
    private var resizeHandle: XCUIElement { element("sidebar.resize") }
    private var sidebarWidth: CGFloat { resizeHandle.frame.maxX - app.windows.firstMatch.frame.minX }

    /// Tabs move by dragging between open tabs, the favorites grid and pinned favorites; a closed favorite keeps
    /// its place; tiles keep their height while columns follow the sidebar's width; all of it survives a relaunch.
    func testTabsMoveBetweenOpenPinnedAndFavorites() throws {
        try launch { seed in
            seed.addTab("solid.html", title: "Solid fixture")
            seed.addTab("favicon.html", title: "Favicon fixture")
            seed.addTab("keys.html", title: "Keys fixture")
            seed.addTab("find.html", title: "Find fixture")
        }
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture", "Favicon fixture", "Keys fixture", "Find fixture"])
        // A shown page, not New Tab, whose search field would take the dragged address.
        tabRows["Find fixture"].click()
        XCTAssertTrue(page("Nothing selected").waitForExistence(timeout: Self.pageTimeout))
        drag(tabRows["Keys fixture"], to: tabRows["Favicon fixture"], at: Self.upperHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Solid fixture", "Keys fixture", "Favicon fixture", "Find fixture"] },
                      "Rows: \(labels(of: "sidebar.tab")); pinned: \(labels(of: "sidebar.favorite")); grid: \(labels(of: "sidebar.tile"))")

        let emptyGrid = element("sidebar.emptyGrid")
        XCTAssertFalse(emptyGrid.exists, "The empty grid is hidden while idle")
        // Pickup reveals the grid's target above the separator.
        let top = pinnedDropZone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 12))
        tabRows["Solid fixture"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click(forDuration: Self.dragHold, thenDragTo: top, withVelocity: .default, thenHoldForDuration: Self.dropHold)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Solid fixture"] }, "Grid: \(labels(of: "sidebar.tile"))")
        XCTAssertFalse(emptyGrid.exists)
        drag(tabRows["Keys fixture"], to: tiles["Solid fixture"], at: Self.leadingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Keys fixture", "Solid fixture"] }, "Tiles part before the one dropped on")
        drag(tabRows["Favicon fixture"], to: tiles["Solid fixture"], at: Self.trailingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Keys fixture", "Solid fixture", "Favicon fixture"] }, "…or after it")
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Find fixture"])

        tiles["Keys fixture"].click()
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.pageTimeout))
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(poll { !self.page("No shortcut yet").exists }, "Closing a favorite unloads its page")
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Keys fixture", "Solid fixture", "Favicon fixture"], "…and keeps it")

        drag(tiles["Solid fixture"], to: app.buttons["sidebar.newTab"], at: Self.lowerHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Solid fixture", "Find fixture"] }, "A favorite dragged to the open tabs leaves the favorites")
        drag(tabRows["Solid fixture"], to: tiles["Favicon fixture"], at: Self.trailingHalf)
        drag(tabRows["Find fixture"], to: tiles["Solid fixture"], at: Self.trailingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Keys fixture", "Favicon fixture", "Solid fixture", "Find fixture"] }, "Grid: \(labels(of: "sidebar.tile"))")
        drag(tiles["Find fixture"], to: tiles["Keys fixture"], at: Self.leadingHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Find fixture", "Keys fixture", "Favicon fixture", "Solid fixture"] }, "Reordering works across rows")
        drag(tiles["Solid fixture"], to: app.buttons["downloads.button"], at: Self.upperHalf)
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Find fixture", "Keys fixture", "Favicon fixture", "Solid fixture"], "A drop outside the tabs changes nothing")

        let first = tiles.element(boundBy: 0).frame
        XCTAssertLessThan(first.height / first.width, 0.8, "Tiles are wider than tall")
        XCTAssertEqual(tiles.element(boundBy: 2).frame.minY, first.minY, accuracy: 1, "Three columns")
        XCTAssertGreaterThan(tiles.element(boundBy: 3).frame.minY, first.maxY)
        attachScreenshot("favorites three columns")
        let start = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 88, dy: 0)))
        XCTAssertTrue(poll { abs(self.tiles.element(boundBy: 3).frame.minY - self.tiles.element(boundBy: 0).frame.minY) < 1 }, "A wider sidebar fits four")
        for tile in tiles.allElementsBoundByIndex { XCTAssertEqual(tile.frame.height, first.height, accuracy: 1, "Tiles keep their height") }
        XCTAssertGreaterThan(tiles.element(boundBy: 0).frame.width, first.width)
        let widened = sidebarWidth
        attachScreenshot("favorites four columns")

        drag(tiles["Solid fixture"], to: pinnedDropZone, at: Self.upperHalf)
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture"] }, "A tile dropped under the grid is pinned")
        favoriteRows["Solid fixture"].click()
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        app.typeKey("w", modifierFlags: .command)
        favoriteRows["Solid fixture"].hover()
        XCTAssertTrue(app.buttons["sidebar.removeFavorite"].waitForExistence(timeout: Self.renderTimeout), "A closed pinned favorite offers its removal")
        attachScreenshot("closed pinned favorite")
        app.buttons["sidebar.removeFavorite"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite").isEmpty })

        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.tile"), ["Find fixture", "Keys fixture", "Favicon fixture"])
        XCTAssertEqual(labels(of: "sidebar.favorite"), [])
        XCTAssertEqual(sidebarWidth, widened, accuracy: 3, "The sidebar keeps its width")
    }

    /// Groups, renaming and duplicating from context menus that show only what applies; the menu bar holds what
    /// it should; the command bar's move asks which group; everything survives a relaunch.
    func testGroupsMenusAndTheMovePrompt() throws {
        try launch { seed in
            seed.addTab("solid.html", title: "Solid fixture")
            seed.addTab("keys.html", title: "Keys fixture")
            try seed.addSpace("Work", profile: "Professional")
        }
        tabRows["Solid fixture"].rightClick()
        expectMenu("context open tab", ["Copy Link", "Duplicate Tab", "Rename Tab…", "Add to Favorites", "Pin Tab", "New Group with Tab", "Move to Space", "Close Tab"],
                   absent: ["Remove from Favorites", "Move to Group"])
        app.windows.menuItems["New Group with Tab"].click()
        let rename = app.textFields["sidebar.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: Self.renderTimeout), "A new group asks for its name")
        replaceText(of: rename, with: "Reading\n")
        XCTAssertTrue(poll { self.labels(of: "sidebar.group") == ["Reading"] })
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture"])
        tabRows["Keys fixture"].rightClick()
        chooseInSubmenu("Move to Group", "Reading")
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture", "Keys fixture"] })

        groupHeaders["Reading"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite").isEmpty }, "The header closes the group")
        groupHeaders["Reading"].rightClick()
        expectMenu("context group", ["Rename Group…", "Expand Group", "Ungroup"])
        app.windows.menuItems["Expand Group"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite").count == 2 })

        chooseInContextMenu(of: favoriteRows["Keys fixture"], "Rename Tab…")
        replaceText(of: rename, with: "Discarded")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture", "Keys fixture"] }, "Escape keeps the name")
        chooseInContextMenu(of: favoriteRows["Keys fixture"], "Rename Tab…")
        replaceText(of: rename, with: "Shortcuts\n")
        favoriteRows["Shortcuts"].click()
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture", "Shortcuts"], "The page's title does not replace the name")
        favoriteRows["Shortcuts"].rightClick()
        expectMenu("context favorite", ["Copy Link", "Duplicate Tab", "Move to Favorites Grid", "Remove from Favorites", "Move to Group", "Move to Space", "Close Tab"],
                   absent: ["Add to Favorites", "Pin Tab"])
        app.windows.menuItems["Duplicate Tab"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab") == ["Shortcuts"] }, "The duplicate is an open tab")
        tabRows["Shortcuts"].click()

        XCTAssertFalse(app.menuBars.menuBarItems["Profiles"].exists, "Settings holds profiles")
        expectMenuBar("File", ["New Tab", "Open Location…", "Command Bar", "Close Tab", "Close Window", "Import from Another Browser…", "Print…"], absent: ["Close All"])
        expectMenuBar("Edit", ["Copy", "Copy Link", "Find"])
        expectMenuBar("View", ["Hide Sidebar", "Reload Page", "Reload Without Cache", "Zoom In", "Actual Size", "Show Downloads", "Site Settings…"])
        expectMenuBar("History", ["Back", "Forward", "Reopen Closed Tab", "Show All History"])
        expectMenuBar("Spaces", ["New Space…", "Main", "Work", "Next Space", "Previous Space"])
        expectMenuBar("Tabs", ["Next Tab", "Add to Favorites", "Duplicate Tab", "Rename Tab…", "New Group with Tab", "Move to Group", "Move to Space",
                               "Close Other Tabs", "Close Tabs Below"],
                      absent: ["Select Tab 1", "Next Recently Used Tab", "Clear Cookies", "Passwords"], keepOpen: true)
        let move = app.menuBars.menuBarItems["Tabs"].menus.menuItems["Move to Space"]
        move.hover()
        XCTAssertTrue(move.menus.menuItems["Work"].waitForExistence(timeout: Self.renderTimeout), "Move to Space lists the spaces")
        XCTAssertFalse(move.menus.menuItems["Main"].isEnabled, "The tab's own space is not a destination")
        attachScreen("menu tabs move to space")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])

        runCommand("Move to Group…")
        let reading = app.buttons.matching(identifier: "tabMove.choice").matching(NSPredicate(format: "label BEGINSWITH %@", "Reading")).firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: Self.renderTimeout), "The prompt lists the groups")
        XCTAssertTrue(reading.isSelected, "The only group is chosen already")
        XCTAssertTrue(app.staticTexts["Shortcuts"].exists, "The prompt names the tab it moves")
        attachScreenshot("move to group prompt")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { self.labels(of: "sidebar.favorite") == ["Solid fixture", "Shortcuts", "Shortcuts"] }, "Return moves the tab")

        space("Main").rightClick()
        expectMenu("context space", ["Edit Space…", "Move Left", "Move Right", "Delete Space…"])
        XCTAssertFalse(app.windows.menuItems["Move Left"].isEnabled, "The first space cannot move left")
        app.typeKey(.escape, modifierFlags: [])

        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.group"), ["Reading"])
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture", "Shortcuts", "Shortcuts"])
        chooseInContextMenu(of: groupHeaders["Reading"], "Ungroup")
        XCTAssertTrue(poll { self.labels(of: "sidebar.group").isEmpty })
        XCTAssertEqual(labels(of: "sidebar.favorite"), ["Solid fixture", "Shortcuts", "Shortcuts"], "Ungrouping keeps the favorites")
    }

    /// The sidebar's controls line up with the window's, hide with it, reveal at the left edge, resize within
    /// limits and fold away, through zoom and full screen; tooltips name each control and its shortcut.
    func testTheSidebarFollowsTheWindow() throws {
        try launch()
        let toggle = app.buttons["sidebar.toggle"], address = app.buttons["sidebar.location"]
        let navigation = ["sidebar.back", "sidebar.forward", "sidebar.reload"].map { app.buttons[$0] }
        let lights = ["window.close", "window.minimize", "window.fullScreen"].map { app.buttons[$0] }
        let window = app.windows["aero.main"]
        func verifyLayout(_ moment: String) {
            // AppKit places its buttons just after the window appears or changes size.
            _ = poll { (navigation + lights).allSatisfy { abs($0.frame.midY - toggle.frame.midY) < 0.5 } }
            for control in navigation + lights {
                XCTAssertTrue(control.isHittable, "\(control.identifier) \(moment)")
                XCTAssertEqual(control.frame.midY, toggle.frame.midY, accuracy: 0.5, "\(control.identifier) lines up \(moment)")
            }
            XCTAssertGreaterThanOrEqual(toggle.frame.minX - lights[2].frame.maxX, 10)
            XCTAssertGreaterThan(address.frame.minY, navigation[2].frame.maxY)
        }

        toggle.hover()
        let tooltip = app.dialogs["tooltip"]
        XCTAssertTrue(tooltip.waitForExistence(timeout: Self.renderTimeout), "Resting on a control shows its tooltip")
        XCTAssertTrue(tooltip.staticTexts["Toggle sidebar"].exists)
        let caps = tooltip.staticTexts.matching(identifier: "keycap")
        XCTAssertEqual((0..<caps.count).map { caps.element(boundBy: $0).value as? String }, ["⌘", "S"], "The tooltip shows the shortcut")
        attachScreenshot("tooltip", of: app)
        navigation[0].hover()
        XCTAssertTrue(tooltip.staticTexts["Back"].waitForExistence(timeout: 0.3), "A neighbour's tooltip follows at once")
        navigation[0].click()
        XCTAssertFalse(tooltip.waitForExistence(timeout: 1), "A click hides it")

        // Accessibility reports the native buttons' frames once the window has handled an event.
        verifyLayout("at launch")
        let pinnedAddress = address.frame
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(poll { !toggle.exists && !address.exists && !lights[0].exists }, "⌘S hides the sidebar and its controls")
        controlBarInput.typeText(server.url("solid.html").absoluteString + "\n")
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertFalse(toggle.exists, "A loaded page adds no control while the sidebar is hidden")
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 4, dy: 0)).hover()
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "The left edge reveals the sidebar")
        XCTAssertEqual(address.frame.minX - pinnedAddress.minX, 12, accuracy: 1, "It floats inset")
        XCTAssertEqual(address.frame.minY - pinnedAddress.minY, 12, accuracy: 1)
        lights[0].hover()
        pause(0.5) // What must not happen: the sidebar closing under the pointer.
        XCTAssertTrue(toggle.exists, "Hovering the window controls keeps it open")
        attachScreenshot("floating sidebar", of: app)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        XCTAssertTrue(poll { !toggle.exists && !lights[0].exists }, "Leaving it hides it again")
        app.typeKey("s", modifierFlags: .command)
        verifyLayout("once shown again")

        let initial = sidebarWidth
        dragHandle(by: 80)
        XCTAssertTrue(poll { self.sidebarWidth > initial + 65 })
        dragHandle(by: 500)
        XCTAssertEqual(sidebarWidth, window.frame.width / 3, accuracy: 3, "At most a third of the window")
        dragHandle(by: -(sidebarWidth - initial + 30))
        XCTAssertEqual(sidebarWidth, initial, accuracy: 3, "At least its default width")
        dragHandle(by: -190)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).hover()
        XCTAssertTrue(poll { !self.resizeHandle.exists }, "Dragging far past the minimum folds it away")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(sidebarWidth, initial, accuracy: 3, "It comes back at its width")

        let frame = window.frame
        chooseInMenuBar("Window", "Zoom")
        XCTAssertTrue(poll { window.frame.size != frame.size })
        verifyLayout("after zooming the window")
        let zoomed = window.frame
        toggleFullScreen()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { window.frame.height > zoomed.height }, "Full screen")
        pause(1) // The system's transition ends after the frame changes.
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(poll { !lights[0].exists }, "Hiding the sidebar in full screen hides its controls")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(lights[0].waitForExistence(timeout: Self.renderTimeout))
        toggleFullScreen()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { abs(window.frame.height - zoomed.height) < 1 }, "Out of full screen")
        pause(1)
        verifyLayout("after full screen")
        lights[0].hover()
        attachScreenshot("window controls after full screen", of: app)
    }

    // MARK: - Helpers

    private func drag(_ source: XCUIElement, to target: XCUIElement, at offset: CGVector) {
        // With an empty grid, pickup reveals a 44-point target plus the section spacing; XCTest resolves the
        // destination before pickup, so follow the row's resulting position.
        let expansion: CGFloat = tiles.count == 0 ? 48 : 0
        let destination = target.coordinate(withNormalizedOffset: offset).withOffset(CGVector(dx: 0, dy: expansion))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: Self.dragHold, thenDragTo: destination, withVelocity: .default, thenHoldForDuration: Self.dropHold)
        // Accessibility reports the final frames before the sidebar's spring settles.
        pause(0.5)
    }

    /// From the View menu, like the green button: resting a synthesized pointer on the button opens the system's
    /// window menu, which would take the keyboard.
    private func toggleFullScreen() {
        let view = app.menuBars.menuBarItems["View"]
        view.click()
        view.menus.menuItems.matching(NSPredicate(format: "title ENDSWITH %@", "Full Screen")).firstMatch.click()
    }

    private func dragHandle(by offset: CGFloat) {
        let start = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: offset, dy: 0)))
    }

    /// Checks the open context menu and keeps its picture; it stays open for the journey's next choice.
    private func expectMenu(_ name: String, _ items: [String], absent: [String] = []) {
        for item in items { XCTAssertTrue(app.windows.menuItems[item].waitForExistence(timeout: Self.renderTimeout), "\(name) shows \(item)") }
        for item in absent { XCTAssertFalse(app.windows.menuItems[item].exists, "\(name) leaves out \(item)") }
        attachScreen(name)
    }

    private func expectMenuBar(_ menu: String, _ items: [String], absent: [String] = [], keepOpen: Bool = false) {
        let bar = app.menuBars.menuBarItems[menu]
        bar.click()
        for item in items { XCTAssertTrue(bar.menus.menuItems[item].waitForExistence(timeout: Self.renderTimeout), "\(menu) shows \(item)") }
        for item in absent { XCTAssertFalse(bar.menus.menuItems[item].exists, "\(menu) leaves out \(item)") }
        attachScreen("menu \(menu.lowercased())")
        if !keepOpen { app.typeKey(.escape, modifierFlags: []) }
    }
}
