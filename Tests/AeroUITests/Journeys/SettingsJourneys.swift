import XCTest

/// Choices that last and how Aero looks: quitting, Settings › General and Tabs, the theme web pages see, the app
/// icon and favorites' colors. See docs/DESIGN.md › App icon and docs/PERFORMANCE.md › Hibernation.
@MainActor
final class SettingsJourneys: E2ETestCase {
    private static let iconVariant = "settings.appIcon.a-sun"
    private static let automaticIcon = "settings.appIcon.automatic"
    /// The Finder's custom icon inside the app bundle, which the Finder, the Dock and Launchpad show.
    private var customIconFile: URL {
        Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Aero Dev.app").appendingPathComponent("Icon\r")
    }

    private func theme(_ name: String) -> XCUIElement { app.radioButtons[name] }
    private func isChosen(_ name: String) -> Bool { theme(name).value as? Int == 1 }

    /// ⌘Q asks first unless told never to; the session, theme, icon, search engine and tab hibernation all survive
    /// quitting.
    func testChoicesSurviveQuitting() throws {
        try launch()
        open("solid.html", expecting: "Solid fixture")
        app.typeKey("q", modifierFlags: .command)
        let prompt = app.groups["quit.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.renderTimeout), "⌘Q asks first")
        attachScreenshot("quit prompt")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(prompt.waitForExistence(timeout: 1), "Escape cancels")

        openSettings("General")
        XCTAssertTrue(app.buttons[Self.automaticIcon].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(isChosen("System"), "The theme follows the system by default")
        XCTAssertTrue(app.buttons[Self.automaticIcon].isSelected, "The icon is automatic by default")
        attachScreenshot("settings general", of: app)
        app.popUpButtons["settings.language"].click()
        app.menuItems["Français"].click()
        XCTAssertTrue(app.staticTexts["settings.languageRestart"].waitForExistence(timeout: Self.renderTimeout), "A new language waits for a restart")
        theme("Dark").click()
        app.popUpButtons["settings.searchEngine"].click()
        app.menuItems["DuckDuckGo"].click()
        reveal(app.buttons[Self.iconVariant]).click()
        XCTAssertTrue(app.buttons[Self.iconVariant].isSelected)
        XCTAssertTrue(poll { FileManager.default.fileExists(atPath: self.customIconFile.path) }, "The icon is set on the app itself, so it shows while Aero is closed")
        selectSettingsSection("updates")
        XCTAssertTrue(app.staticTexts["updates.disabled"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["updates.check"].isEnabled, "Test builds cannot reach the production updater")
        XCTAssertFalse(app.switches["updates.automaticChecks"].exists, "Disabled updaters have no misleading preferences")
        attachScreenshot("updates disabled in development", of: app)
        selectSettingsSection("Tabs")
        let hibernation = app.switches["settings.hibernation.enabled"], idleLimit = app.popUpButtons["settings.hibernation.idleLimit"]
        XCTAssertTrue(hibernation.waitForExistence(timeout: Self.renderTimeout))
        hibernation.click()
        XCTAssertFalse(idleLimit.isEnabled, "Its options follow the switch")
        XCTAssertFalse(app.switches["settings.hibernation.keepsFavorites"].isEnabled)
        closeSettings()
        XCTAssertFalse(app.popUpButtons["settings.language"].exists, "⌘W closes Settings")

        app.webViews.firstMatch.click()
        quitAndRelaunch() // Return quits even with the page focused.
        XCTAssertTrue(tabRows["Solid fixture"].exists, "The session was saved")
        openSettings("General")
        XCTAssertTrue(app.buttons[Self.automaticIcon].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(isChosen("Dark"), "The theme survives")
        XCTAssertTrue(app.buttons[Self.iconVariant].isSelected, "The icon survives")
        XCTAssertEqual(app.popUpButtons["settings.searchEngine"].value as? String, "DuckDuckGo", "The engine survives")
        reveal(app.buttons[Self.automaticIcon]).click()
        XCTAssertTrue(poll { !FileManager.default.fileExists(atPath: self.customIconFile.path) }, "Automatic gives the system its icon back")
        selectSettingsSection("Tabs")
        XCTAssertTrue(idleLimit.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(idleLimit.isEnabled, "Hibernation stays off")
        closeSettings()

        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["quit.never"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout))
        relaunch()
        openSettings("General")
        XCTAssertEqual(app.switches["settings.confirmsQuit"].value as? Int, 0, "Settings shows the prompt is off")
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout), "⌘Q then quits at once")
    }

    /// Pages see the theme chosen, and System removes any override; a favorite's outline takes its icon's color,
    /// cached across relaunches, in both appearances.
    func testPagesAndFavoritesFollowTheAppearance() throws {
        try launch()
        open("appearance.html", expecting: "Appearance fixture")
        XCTAssertTrue(poll { self.page("Page is dark").exists || self.page("Page is light").exists })
        let systemScheme = page("Page is dark").exists ? "Page is dark" : "Page is light"
        for choice in ["Dark", "Light"] {
            openSettings("General")
            theme(choice).click()
            closeSettings()
            XCTAssertTrue(page(choice == "Dark" ? "Page is dark" : "Page is light").waitForExistence(timeout: Self.renderTimeout), "The page is \(choice)")
            openSettings("General")
            theme("System").click()
            closeSettings()
            XCTAssertTrue(page(systemScheme).waitForExistence(timeout: Self.renderTimeout), "System removes the \(choice) override")
        }

        open("favicon.html", expecting: "Favicon fixture")
        app.typeKey("d", modifierFlags: .command)
        let tile = tiles["Favicon fixture"]
        XCTAssertTrue(tile.waitForExistence(timeout: Self.renderTimeout))
        app.webViews.firstMatch.hover()
        let outline = ScreenshotColor(red: 166, green: 80, blue: 33)
        XCTAssertTrue(poll { outline.isShown(in: tile, at: CGPoint(x: tile.frame.width / 2, y: 0.5)) }, "The orange favicon gives the active outline")
        attachScreenshot("favorite light", of: app)
        app.typeKey("t", modifierFlags: .command)
        controlBarInput.hover()
        let idle = ScreenshotColor(red: 222, green: 222, blue: 222)
        XCTAssertTrue(poll { idle.isShown(in: tile, at: CGPoint(x: 6, y: tile.frame.height / 2)) }, "An inactive favorite is neutral")

        quitAndRelaunch()
        tile.click()
        app.webViews.firstMatch.hover()
        XCTAssertTrue(poll { outline.isShown(in: tile, at: CGPoint(x: tile.frame.width / 2, y: 0.5)) }, "The outline comes from the cached favicon")
        quitAndRelaunch { $0.dark = true }
        tile.click()
        app.webViews.firstMatch.hover()
        XCTAssertTrue(tile.isSelected)
        attachScreenshot("favorite dark", of: app)
        tile.hover()
        pause(0.25) // The hover fades in before its color is captured.
        attachScreenshot("favorite dark hover", of: app)
    }
}
