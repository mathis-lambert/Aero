import XCTest

@MainActor
final class BrowserUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        await MainActor.run {
            continueAfterFailure = false
            app = TestApplication.make()
            app.launch()
            XCTAssertTrue(app.textFields["newTab.input"].waitForExistence(timeout: TestApplication.launchTimeout))
        }
    }

    override func tearDown() async throws { await MainActor.run { app.terminate() } }

    func testCommandBarKeyboardAndEscape() {
        app.typeKey("k", modifierFlags: .command)
        let input = app.textFields["command.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.typeText("example.com")
        XCTAssertEqual(input.value as? String, "example.com")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(input.exists)
        XCTAssertTrue(app.textFields["newTab.input"].exists)
    }

    /// The palette searches the whole command catalog, not a fixed selection.
    func testCommandPaletteRunsAnyCatalogCommand() {
        app.typeKey("k", modifierFlags: .command)
        let input = app.textFields["command.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.typeText("history")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        let historyTab = app.buttons.matching(identifier: "sidebar.tab").matching(NSPredicate(format: "label == %@", "History")).firstMatch
        XCTAssertTrue(historyTab.waitForExistence(timeout: 3), "The first command after the search opens History")
        XCTAssertFalse(input.exists)
    }

    func testCreateRenameAndRestoreProfile() {
        openProfiles()
        app.buttons["profiles.add"].click()
        app.textFields["profiles.name"].click()
        app.typeText("Work")
        app.buttons["profiles.save"].click()
        XCTAssertEqual(app.buttons["sidebar.profiles"].value as? String, "Work")

        openProfiles()
        let name = app.textFields["profiles.name"]
        name.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Studio")
        app.buttons["profiles.save"].click()
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        app.launch()
        XCTAssertTrue(app.textFields["newTab.input"].waitForExistence(timeout: TestApplication.launchTimeout))
        openProfiles()
        XCTAssertTrue(app.buttons["profiles.row.Studio"].exists)
    }

    func testProfileFormRejectsEmptyName() {
        openProfiles()
        app.buttons["profiles.add"].click()
        XCTAssertFalse(app.buttons["profiles.save"].isEnabled)
    }

    func testFrenchNewTab() {
        app.terminate()
        app.launchArguments = TestApplication.languageArguments(language: "fr", locale: "fr_FR")
        app.launch()
        XCTAssertTrue(app.textFields["newTab.input"].waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertTrue(app.buttons["sidebar.newTab"].label.contains("Nouvel onglet"))
        XCTAssertEqual(app.textFields["newTab.input"].placeholderValue, "Rechercher ou saisir une adresse")
    }

    func testNewTabKeyboardFocus() {
        app.typeKey("t", modifierFlags: .command)
        let input = app.textFields["newTab.input"]
        input.typeText("example.com")
        XCTAssertEqual(input.value as? String, "example.com")
    }

    func testSidebarNavigationAndWindowControls() {
        let window = app.windows["aero.main"]
        let sidebarToggle = app.buttons["sidebar.toggle"]
        let profile = app.buttons["sidebar.profiles"]
        let address = app.buttons["sidebar.location"]
        let navigation = ["sidebar.back", "sidebar.forward", "sidebar.reload"].map { app.buttons[$0] }
        let lights = ["window.close", "window.minimize", "window.fullScreen"]
            .map { app.buttons[$0] }

        func verifyVisibleLayout() {
            let centerY = sidebarToggle.frame.midY
            for control in navigation {
                XCTAssertEqual(control.frame.midY, centerY, accuracy: 0.5, control.identifier)
            }
            for light in lights {
                XCTAssertTrue(light.exists)
                XCTAssertTrue(light.isHittable)
                XCTAssertEqual(light.frame.midY, centerY, accuracy: 0.5)
            }
            XCTAssertGreaterThanOrEqual(sidebarToggle.frame.minX - lights[2].frame.maxX, 10)
            XCTAssertLessThan(navigation[2].frame.maxX, window.frame.minX + 224)
            XCTAssertTrue(address.exists)
            XCTAssertGreaterThan(address.frame.minY, navigation[2].frame.maxY)
            XCTAssertGreaterThan(profile.frame.minY, address.frame.maxY)
            XCTAssertFalse(window.buttons[XCUIIdentifierCloseWindow].exists, "The titlebar's own buttons stay hidden")
            XCTAssertFalse(app.buttons["page.showSidebar"].exists)
        }

        verifyVisibleLayout()
        app.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.buttons["page.showSidebar"].exists)
        XCTAssertFalse(sidebarToggle.exists)
        XCTAssertFalse(address.exists)
        for light in lights { XCTAssertFalse(light.exists) }
        app.textFields["newTab.input"].typeText("https://example.com\n")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["page.showSidebar"].exists)
        app.typeKey("s", modifierFlags: [.command, .shift])
        verifyVisibleLayout()

        let originalFrame = window.frame
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Zoom"].click()
        XCTAssertNotEqual(window.frame.size, originalFrame.size)
        verifyVisibleLayout()
    }

    func testHiddenSidebarRevealsAtLeftEdge() {
        let pinnedAddress = app.buttons["sidebar.location"].frame
        app.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.buttons["sidebar.toggle"].exists)
        let window = app.windows["aero.main"]
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 4, dy: 0)).hover()
        XCTAssertTrue(app.buttons["sidebar.toggle"].waitForExistence(timeout: 3))
        let floatingAddress = app.buttons["sidebar.location"].frame
        XCTAssertEqual(floatingAddress.minX - pinnedAddress.minX, 12, accuracy: 1)
        XCTAssertEqual(floatingAddress.minY - pinnedAddress.minY, 12, accuracy: 1)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        XCTAssertFalse(app.buttons["sidebar.toggle"].exists)
    }

    func testSettingsSectionsAndLanguagePreference() {
        app.typeKey(",", modifierFlags: .command)
        let language = app.popUpButtons["settings.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.click()
        app.menuItems["Français"].click()
        XCTAssertTrue(app.staticTexts["settings.languageRestart"].waitForExistence(timeout: 3))
        app.buttons["settings.appearance"].click()
        app.buttons["settings.theme.light"].click()
        app.buttons["settings.shortcuts"].click()
        XCTAssertTrue(app.staticTexts["The essentials, always within reach."].exists)
        app.buttons["settings.profiles"].click()
        app.buttons["settings.manageProfiles"].click()
        XCTAssertTrue(app.buttons["profiles.add"].waitForExistence(timeout: 3), "Settings opens the same profile sheet")
    }

    func testPerformanceSettingsPersistAcrossLaunches() {
        app.typeKey(",", modifierFlags: .command)
        app.buttons["settings.performance"].click()
        let enabled = app.checkBoxes["settings.hibernation.enabled"]
        let idleLimit = app.popUpButtons["settings.hibernation.idleLimit"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 3))
        XCTAssertTrue(idleLimit.isEnabled)
        enabled.click()
        XCTAssertFalse(idleLimit.isEnabled)
        XCTAssertFalse(app.checkBoxes["settings.hibernation.keepsPinned"].isEnabled)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["newTab.input"].waitForExistence(timeout: TestApplication.launchTimeout))
        app.typeKey(",", modifierFlags: .command)
        app.buttons["settings.performance"].click()
        XCTAssertTrue(idleLimit.waitForExistence(timeout: 3))
        XCTAssertFalse(idleLimit.isEnabled)
    }

    private func openProfiles() {
        app.menuBars.menuBarItems["Navigate"].click()
        app.menuItems["Manage profiles"].click()
        XCTAssertTrue(app.buttons["profiles.add"].waitForExistence(timeout: 3))
    }
}
