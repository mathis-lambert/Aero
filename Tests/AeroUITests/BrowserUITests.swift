import XCTest

/// Localization, the sidebar and window controls, tooltips, the quit prompt and Settings.
@MainActor
final class BrowserUITests: BrowserE2ETestCase {
    func testTooltipsShowLabelAndShortcut() {
        let toggle = app.buttons["sidebar.toggle"]
        toggle.hover()
        let tooltip = app.dialogs["tooltip"]
        XCTAssertTrue(tooltip.waitForExistence(timeout: Self.renderTimeout), "Resting on a control shows its tooltip")
        XCTAssertTrue(tooltip.staticTexts["Toggle sidebar"].exists)
        let caps = tooltip.staticTexts.matching(identifier: "keycap")
        XCTAssertEqual((0..<caps.count).map { caps.element(boundBy: $0).value as? String }, ["⇧", "⌘", "S"],
                       "The keys of the menu's shortcut")
        attachScreenshot("tooltip", of: app)
        app.buttons["sidebar.back"].hover()
        XCTAssertTrue(tooltip.staticTexts["Back"].waitForExistence(timeout: 0.3), "A neighbour's tooltip follows at once")
        app.buttons["sidebar.back"].click()
        XCTAssertFalse(tooltip.waitForExistence(timeout: 1), "A click hides it")
    }

    func testQuitAsksFirst() {
        open("solid.html", expecting: "Solid fixture")
        app.typeKey("q", modifierFlags: .command)
        let prompt = app.groups["quit.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.renderTimeout), "⌘Q asks first")
        attachScreenshot("quit-prompt")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(prompt.waitForExistence(timeout: 1), "Escape cancels")
        XCTAssertEqual(app.state, .runningForeground)

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout), "Return quits, even with a page focused")

        app.launch()
        XCTAssertTrue(tabRows.firstMatch.waitForExistence(timeout: TestApplication.launchTimeout), "The session was saved")
        app.typeKey("q", modifierFlags: .command)
        app.buttons["quit.never"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout))

        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        openSettings("General")
        let toggle = app.switches["settings.confirmsQuit"]
        XCTAssertTrue(toggle.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(toggle.value as? Int, 0, "Settings shows the prompt is off")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout), "⌘Q then quits at once")
    }

    func testFrenchNewTab() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertTrue(app.buttons["sidebar.newTab"].label.contains("Nouvel onglet"))
        XCTAssertEqual(controlBarInput.placeholderValue, "Rechercher ou saisir une adresse")
    }

    func testSidebarNavigationAndWindowControls() {
        let window = app.windows["aero.main"]
        let sidebarToggle = app.buttons["sidebar.toggle"]
        let profile = app.buttons.matching(identifier: "sidebar.profile").firstMatch
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
        }

        verifyVisibleLayout()
        app.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertFalse(sidebarToggle.exists)
        XCTAssertFalse(address.exists)
        for light in lights { XCTAssertFalse(light.exists) }
        controlBarInput.typeText(server.url("solid.html").absoluteString + "\n")
        XCTAssertTrue(app.webViews.staticTexts["Solid fixture"].waitForExistence(timeout: Self.pageTimeout))
        XCTAssertFalse(sidebarToggle.exists, "A loaded page adds no control while the sidebar is hidden")
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
        openSettings("General")
        let language = app.popUpButtons["settings.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        attachScreenshot("settings-general-compact")
        language.click()
        app.menuItems["Français"].click()
        XCTAssertTrue(app.staticTexts["settings.languageRestart"].waitForExistence(timeout: 3))
        app.radioButtons["Light"].click()
        attachScreenshot("settings-general-light", of: app)
        app.toolbars.buttons["Tabs"].click()
        XCTAssertTrue(app.switches["settings.hibernation.enabled"].waitForExistence(timeout: 3))
        attachScreenshot("settings-tabs", of: app)
        app.toolbars.buttons["Profiles"].click()
        XCTAssertTrue(app.buttons["profiles.add"].waitForExistence(timeout: 3), "Settings edits profiles in place")
        attachScreenshot("settings-profiles", of: app)

        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        openSettings("Général")
        XCTAssertTrue(app.popUpButtons["settings.language"].waitForExistence(timeout: 3), "Settings is in French")
        attachScreenshot("settings-general-french", of: app)
        closeSettings()
        XCTAssertFalse(app.popUpButtons["settings.language"].waitForExistence(timeout: 1), "⌘W closes Settings")
        openSettings()
        XCTAssertTrue(app.popUpButtons["settings.language"].waitForExistence(timeout: 3), "⌘, opens it again")
    }

    func testPerformanceSettingsPersistAcrossLaunches() {
        openSettings("Tabs")
        let enabled = app.switches["settings.hibernation.enabled"]
        let idleLimit = app.popUpButtons["settings.hibernation.idleLimit"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 3))
        XCTAssertTrue(idleLimit.isEnabled)
        enabled.click()
        XCTAssertFalse(idleLimit.isEnabled)
        XCTAssertFalse(app.switches["settings.hibernation.keepsPinned"].isEnabled)

        relaunch()
        openSettings("Tabs")
        XCTAssertTrue(idleLimit.waitForExistence(timeout: 3))
        XCTAssertFalse(idleLimit.isEnabled)
    }
}
