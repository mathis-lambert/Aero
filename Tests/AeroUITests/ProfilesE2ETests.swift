import SQLite3
import XCTest

@MainActor
final class ProfilesE2ETests: BrowserE2ETestCase {
    func testSharedHistoryAndSeparateTabsRestore() {
        open("history-lake.html", expecting: "Alpine Lake fixture")
        createSpace("Reading")
        XCTAssertTrue(labels(of: "sidebar.tab").isEmpty)
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] })
        space("Main").click()
        XCTAssertTrue(page("Alpine Lake fixture").waitForExistence(timeout: Self.pageTimeout))
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main", "Reading"])
        attachScreenshot("shared-profile-spaces")
    }

    func testInlineProfileCreationAndCancellation() {
        createSpace("Work", newProfile: "Professional")
        open("history-city.html", expecting: "Été à Lyon fixture")
        space("Main").click()
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["sidebar.addSpace"].click()
        app.buttons["spaces.newProfile"].click()
        app.textFields["spaces.profileName"].click()
        app.textFields["spaces.profileName"].typeText("Canceled")
        app.typeKey(.escape, modifierFlags: [])
        openSettings("profiles")
        XCTAssertFalse(app.buttons["profiles.row.Canceled"].exists)
        XCTAssertTrue(app.buttons["profiles.row.Professional"].exists)
        attachScreenshot("profiles-settings")
    }

    func testProfileCreationDoesNotCreateSpace() {
        openSettings("profiles")
        app.buttons["profiles.add"].click()
        attachScreenshot("native-profile-creation-sheet")
        app.textFields["profiles.name"].click()
        app.typeText("Unused")
        app.buttons["profiles.save"].click()
        XCTAssertTrue(app.buttons["profiles.delete"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["profiles.save"].exists)
        closeSettings()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main"])
    }

    func testSettingsReassignsSpaceToExistingProfile() {
        openSettings("profiles")
        app.buttons["profiles.add"].click()
        app.textFields["profiles.name"].click()
        app.typeText("Separate")
        app.buttons["profiles.save"].click()
        XCTAssertTrue(app.buttons["profiles.delete"].waitForExistence(timeout: Self.renderTimeout))
        selectSettingsSection("spaces")
        app.buttons["spaces.row.Main"].click()
        let picker = app.popUpButtons["spaces.profile"]
        picker.click()
        picker.menuItems["Separate"].click()
        XCTAssertFalse(app.buttons["Reload pages"].exists, "An empty space needs no reload confirmation")
        selectSettingsSection("profiles")
        app.buttons["profiles.row.Separate"].click()
        XCTAssertFalse(app.buttons["profiles.delete"].isEnabled)
        app.buttons["settings.back"].click()
        app.buttons["profiles.row.Personal"].click()
        XCTAssertTrue(app.buttons["profiles.delete"].isEnabled)
        attachScreenshot("settings-space-reassignment")
    }

    func testMoveWithinProfilePreservesLoadedPage() {
        open("space-state.html", expecting: "Fresh page")
        app.webViews.buttons["Change page state"].click()
        XCTAssertTrue(page("Modified page").exists)
        createSpace("Reading")
        space("Main").click()
        XCTAssertTrue(poll { self.space("Main").isSelected })
        attachScreenshot("selected-main-before-transfer")
        XCTAssertTrue(page("Modified page").waitForExistence(timeout: Self.pageTimeout))
        app.menuBars.menuBarItems["Tabs"].click()
        app.menuItems["Move tab to space…"].click()
        app.sheets.buttons["Reading"].click()
        space("Reading").click()
        XCTAssertTrue(poll { self.space("Reading").isSelected })
        XCTAssertTrue(tabRows.firstMatch.waitForExistence(timeout: Self.renderTimeout))
        tabRows.firstMatch.click()
        XCTAssertTrue(page("Modified page").waitForExistence(timeout: Self.pageTimeout), "Moving inside a profile preserves the live page")
        attachScreenshot("space-tab-transfer")
    }

    func testCrossProfileTransferConfirmsAndRecreatesPage() {
        open("site.html", expecting: "No cookie")
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").exists)
        createSpace("Work", newProfile: "Professional")
        space("Main").click()
        app.menuBars.menuBarItems["Tabs"].click()
        app.menuItems["Move tab to space…"].click()
        app.sheets.buttons["Work"].click()
        XCTAssertTrue(app.buttons["spaces.confirmTransfer"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(page("Cookie set").exists, "Cancel preserves the source page and identity")
        app.menuBars.menuBarItems["Tabs"].click()
        app.menuItems["Move tab to space…"].click()
        app.sheets.buttons["Work"].click()
        app.buttons["spaces.confirmTransfer"].click()
        space("Work").click()
        tabRows.firstMatch.click()
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout))
        attachScreenshot("cross-profile-tab-transfer")
    }

    func testCookiesSharedAndReassignmentChangesIdentity() {
        open("site.html", expecting: "No cookie")
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").exists)
        createSpace("Reading")
        open("site.html", expecting: "Cookie set")
        space("Reading").rightClick()
        app.menuItems["Edit space…"].click()
        reassignToNewProfile("Separate", space: "Reading")
        closeSettings()
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout))
        space("Main").click()
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.pageTimeout))
        attachScreenshot("space-profile-isolation")
    }

    func testHistoryReassignmentResetsSearchAndEntries() {
        open("history-lake.html", expecting: "Alpine Lake fixture")
        app.typeKey("y", modifierFlags: .command)
        let search = app.textFields["history.search"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.renderTimeout))
        search.typeText("alpine")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] })
        space("Main").rightClick()
        app.menuItems["Edit space…"].click()
        reassignToNewProfile("Separate", space: "Main")
        closeSettings()
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(search.value as? String, "")
        attachScreenshot("history-space-reassignment")
    }

    func testDeletionGuardsAndUnusedProfileRemoval() throws {
        space("Main").rightClick()
        XCTAssertFalse(app.menuItems["Delete space…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        createSpace("Temporary", newProfile: "Temporary identity")
        open("history-city.html", expecting: "Été à Lyon fixture")
        openSettings("profiles")
        app.buttons["profiles.row.Temporary identity"].click()
        XCTAssertFalse(app.buttons["profiles.delete"].isEnabled)
        closeSettings()
        space("Temporary").rightClick()
        app.menuItems["Delete space…"].click()
        app.buttons["spaces.confirmDelete"].click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.space") == ["Main"] })
        openSettings("profiles")
        app.buttons["profiles.row.Temporary identity"].click()
        app.buttons["profiles.delete"].click()
        app.sheets.buttons["Delete profile"].click()
        XCTAssertTrue(app.buttons["profiles.row.Personal"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["profiles.row.Temporary identity"].exists)
        let back = app.buttons["settings.back"]
        if back.isEnabled {
            back.click()
            XCTAssertFalse(app.textFields["profiles.name"].exists, "Back must skip the deleted profile detail")
            app.buttons["settings.forward"].click()
            XCTAssertTrue(app.buttons["profiles.row.Personal"].waitForExistence(timeout: Self.renderTimeout))
        }
        app.buttons["profiles.row.Personal"].click()
        XCTAssertFalse(app.buttons["profiles.delete"].isEnabled)
        let root = try XCTUnwrap(app.launchEnvironment[TestApplication.testDataKey])
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(root + "/Storage/History.sqlite", &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM pages", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 0, "Deleting the profile erases its history")
        attachScreenshot("last-profile-protected")
        closeSettings()
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main"])
    }

    func testSpaceEditorWithFrenchAndRightToLeftLayout() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
            + ["-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"]
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        app.buttons["sidebar.addSpace"].click()
        let name = app.textFields["spaces.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.renderTimeout))
        name.click()
        name.typeText("Recherche et documentation")
        XCTAssertTrue(app.buttons["spaces.newProfile"].isHittable)
        XCTAssertTrue(app.buttons["spaces.save"].isHittable)
        attachScreenshot("space-editor-french-rtl")
        app.buttons["spaces.save"].click()
        XCTAssertTrue(poll { self.space("Recherche et documentation").isSelected })
    }

    func testSpaceRenameAndRepeatedSwitches() {
        open("solid.html", expecting: "Solid fixture")
        createSpace("Reading")
        open("keys.html", expecting: "No shortcut yet")
        for _ in 0..<8 {
            space("Main").click()
            XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
            space("Reading").click()
            XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.pageTimeout))
        }
        space("Reading").rightClick()
        app.menuItems["Edit space…"].click()
        let name = app.textFields["spaces.name"]
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Research")
        app.typeKey(.return, modifierFlags: [])
        closeSettings()
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main", "Research"])
        attachScreenshot("spaces-restored")
    }
    private func reassignToNewProfile(_ name: String, space: String) {
        selectSettingsSection("profiles")
        app.buttons["profiles.add"].click()
        app.textFields["profiles.name"].click()
        app.typeText(name)
        app.buttons["profiles.save"].click()
        XCTAssertTrue(app.buttons["profiles.delete"].waitForExistence(timeout: Self.renderTimeout))
        selectSettingsSection("spaces")
        app.buttons["spaces.row.\(space)"].click()
        let picker = app.popUpButtons["spaces.profile"]
        picker.click()
        picker.menuItems[name].click()
        app.sheets.buttons["Reload pages"].click()
    }

}
