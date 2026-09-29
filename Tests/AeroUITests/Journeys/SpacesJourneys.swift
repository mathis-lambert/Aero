import SQLite3
import XCTest

/// Spaces share their profile's identity; profiles keep theirs apart; Settings manages both. The session rules
/// are covered by BrowserSessionTests. See docs/SPACES.md.
@MainActor
final class SpacesJourneys: E2ETestCase {
    private var choices: XCUIElementQuery { app.buttons.matching(identifier: "tabMove.choice") }

    private func choice(_ space: String) -> XCUIElement { choices.matching(NSPredicate(format: "label BEGINSWITH %@", space)).firstMatch }

    /// A new space of the same profile shares its history and cookies and takes a live page along; a space of a
    /// new profile has neither, and moving a tab there asks first and loads it again in that identity.
    func testSpacesShareTheirProfileAndProfilesKeepIdentitiesApart() throws {
        try launch()
        open("site.html", expecting: "No cookie")
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.renderTimeout))
        open("space-state.html", expecting: "Fresh page")
        app.webViews.buttons["Change page state"].click()
        XCTAssertTrue(page("Modified page").waitForExistence(timeout: Self.renderTimeout))

        createSpace("Reading")
        XCTAssertTrue(labels(of: "sidebar.tab").isEmpty, "A space has its own tabs")
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(poll { self.labels(of: "history.row").count == 2 }, "…and its profile's history")
        app.typeKey("w", modifierFlags: .command)
        space("Main").click()
        XCTAssertTrue(page("Modified page").waitForExistence(timeout: Self.pageTimeout))
        app.menuBars.menuBarItems["Tabs"].click()
        chooseInSubmenu("Move to Space", "Reading", in: app.menuBars)
        space("Reading").click()
        tabRows["Space state"].click()
        XCTAssertTrue(page("Modified page").waitForExistence(timeout: Self.pageTimeout), "Moving inside a profile keeps the live page")
        open("site.html", expecting: "Cookie set")

        app.buttons["sidebar.addSpace"].click()
        app.buttons["spaces.newProfile"].click()
        app.textFields["spaces.profileName"].click()
        app.typeText("Canceled")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["spaces.name"].waitForNonExistence(timeout: Self.renderTimeout), "Escape cancels the prompt, even from a field")
        createSpace("Work", newProfile: "Professional")
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout), "Another profile has its own history")
        open("site.html", expecting: "No cookie")
        attachScreenshot("profile isolation")

        space("Reading").click()
        tabRows["Site fixture"].click()
        runCommand("Move to Space…")
        XCTAssertTrue(choice("Main").waitForExistence(timeout: Self.renderTimeout), "The move asks where to")
        XCTAssertTrue(choice("Main").isSelected, "The first other space is chosen")
        XCTAssertFalse(choice("Reading").isEnabled, "The tab's own space is marked, not offered")
        attachScreenshot("move to space prompt")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll { self.choice("Work").isSelected }, "Down chooses the next space")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["spaces.confirmTransfer"].waitForExistence(timeout: Self.renderTimeout), "Another profile asks first")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["spaces.confirmTransfer"].waitForNonExistence(timeout: Self.renderTimeout), "Escape cancels the move")
        XCTAssertTrue(page("Cookie set").exists, "Cancel keeps the page and its identity")
        runCommand("Move to Space…")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        app.buttons["spaces.confirmTransfer"].click()
        space("Work").click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab").filter { $0 == "Site fixture" }.count == 2 })
        tabRows.matching(NSPredicate(format: "label == %@", "Site fixture")).element(boundBy: 0).click()
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "The page loads again in its new identity")

        openSettings("profiles")
        XCTAssertTrue(app.buttons["profiles.row.Professional"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["profiles.row.Canceled"].exists, "A cancelled profile is not created")
        closeSettings()
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main", "Reading", "Work"])
    }

    /// Settings creates and renames profiles, orders, renames and decorates spaces, moves a space to another
    /// profile, which changes its identity and history, and deletes only what may go.
    func testSettingsManageProfilesAndSpaces() throws {
        try launch { seed in
            try seed.addSpace("Reading")
            try seed.addSpace("Spare")
            seed.addTab("site.html", title: "Site fixture")
        }
        tabRows["Site fixture"].click()
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.pageTimeout))
        app.typeKey("y", modifierFlags: .command)
        let search = app.textFields["history.search"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.renderTimeout))
        search.typeText("site")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Site fixture"] })

        openSettings("profiles")
        app.buttons["profiles.add"].click()
        attachScreenshot("profile creation", of: app)
        replaceText(of: app.textFields["profiles.name"], with: "Separate")
        app.buttons["profiles.save"].click()
        XCTAssertTrue(app.buttons["profiles.delete"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["settings.back"].click()
        app.buttons["profiles.row.Personal"].click()
        replaceText(of: app.textFields["profiles.name"], with: "Personal identity")
        // Leaving the detail commits without Save or Return.
        app.buttons["settings.back"].click()
        XCTAssertTrue(app.buttons["profiles.row.Personal identity"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main", "Reading", "Spare"], "A new profile creates no space")

        app.buttons["profiles.row.Personal identity"].click()
        app.buttons["Manage spaces…"].click()
        dragSpace("Reading", above: "Main")
        XCTAssertTrue(poll { self.app.buttons["spaces.row.Reading"].frame.minY < self.app.buttons["spaces.row.Main"].frame.minY }, "Dragging orders the spaces")
        app.buttons["spaces.row.Reading"].click()
        replaceText(of: app.textFields["spaces.name"], with: "Research")
        app.typeKey(.return, modifierFlags: [])
        app.textFields["spaces.emoji"].click()
        app.typeText("🚀")
        app.typeKey(.tab, modifierFlags: [])
        let well = app.colorWells["spaces.customColor"]
        let initial = well.value as? String
        well.click()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: Self.renderTimeout), "The color well opens the system popover, not the panel")
        // A swatch of the popover's grid, away from its edges and its Show Colors button.
        popover.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).click()
        XCTAssertTrue(poll { (well.value as? String) != initial })
        let chosen = components(well.value)
        app.typeKey(.escape, modifierFlags: [])
        attachScreenshot("space detail", of: app)
        app.buttons["settings.back"].click()

        app.buttons["spaces.row.Main"].click()
        let profile = app.popUpButtons["spaces.profile"]
        profile.click()
        profile.menuItems["Separate"].click()
        app.sheets.buttons["Reload pages"].click()
        selectSettingsSection("profiles")
        app.buttons["profiles.row.Separate"].click()
        XCTAssertFalse(app.buttons["profiles.delete"].isEnabled, "A profile in use cannot be deleted")
        closeSettings()
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout), "Main now has the new profile's history")
        XCTAssertEqual(search.value as? String ?? "", "", "…and not the old search")
        tabRows["Site fixture"].click()
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "…and its cookies")

        chooseInContextMenu(of: space("Spare"), "Delete Space…")
        app.buttons["spaces.confirmDelete"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.space") == ["Research", "Main"] })
        openSettings("profiles")
        app.buttons["profiles.row.Personal identity"].click()
        XCTAssertFalse(app.buttons["profiles.delete"].isEnabled, "A profile with a space cannot be deleted")
        closeSettings()
        chooseInContextMenu(of: space("Main"), "Edit Space…")
        let owner = app.popUpButtons["spaces.profile"]
        owner.click()
        owner.menuItems["Personal identity"].click()
        app.sheets.buttons["Reload pages"].click()
        selectSettingsSection("profiles")
        app.buttons["profiles.row.Separate"].click()
        app.buttons["profiles.delete"].click()
        app.sheets.buttons["Delete profile"].click()
        XCTAssertTrue(app.buttons["profiles.row.Personal identity"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["profiles.row.Separate"].exists)
        if app.buttons["settings.back"].isEnabled {
            app.buttons["settings.back"].click()
            XCTAssertFalse(app.textFields["profiles.name"].exists, "Back skips the deleted profile's page")
        }
        XCTAssertEqual(try historyPages(), 1, "Deleting a profile erases its history, and only its history")
        closeSettings()

        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Research", "Main"])
        let research = space("Research"), main = space("Main")
        XCTAssertEqual((research.frame.midX + main.frame.midX) / 2, app.buttons["sidebar.newTab"].frame.midX, accuracy: 3, "Space icons are centered")
        openSettings("spaces")
        app.buttons["spaces.row.Research"].click()
        XCTAssertEqual(app.textFields["spaces.emoji"].value as? String, "🚀")
        // Stored as #RRGGBB: each component comes back to within half an 8-bit step.
        let restored = components(app.colorWells["spaces.customColor"].value)
        XCTAssertEqual(restored.count, 3)
        for (value, expected) in zip(restored, chosen) { XCTAssertEqual(value, expected, accuracy: 0.5 / 255 + 0.0001) }
    }

    // MARK: - Helpers

    private func dragSpace(_ name: String, above destination: String) {
        XCTAssertTrue(app.buttons["spaces.row.\(name)"].waitForExistence(timeout: Self.renderTimeout))
        let source = app.images["spaces.drag.\(name)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = app.images["spaces.drag.\(destination)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -7))
        source.click(forDuration: 0.5, thenDragTo: target)
    }

    /// A color well's value reads "rgb R G B A".
    private func components(_ value: Any?) -> [Double] {
        ((value as? String) ?? "").split(separator: " ").dropFirst().prefix(3).compactMap { Double($0) }
    }

    /// Pages in the history database, read from the file itself.
    private func historyPages() throws -> Int32 {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dataRoot.appendingPathComponent("Storage/History.sqlite").path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM pages", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return sqlite3_column_int(statement, 0)
    }
}
