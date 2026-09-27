import XCTest

/// Exercises native menus, key capture, WebKit precedence, and real namespaced preference reloads.
@MainActor
final class ShortcutE2ETests: BrowserE2ETestCase {
    func testZoomAndSidebarAreReservedWhilePageShortcutsStillWork() {
        open("shortcuts.html", expecting: "Shortcuts fixture")
        let editor = app.webViews.textFields["Editor"]
        editor.click()
        editor.typeText("été déjà vu")
        XCTAssertEqual(editor.value as? String, "été déjà vu", "Ordinary accented text does not enter the shortcut router")
        let target = app.webViews.buttons["Zoom target"]
        let width = target.frame.width
        target.click()
        app.typeKey("=", modifierFlags: .command)
        XCTAssertTrue(poll { target.frame.width > width * 1.05 }, "Command-equals zooms despite the page claiming every Command key")
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(poll { abs(target.frame.width - width) < 2 })
        app.typeKey("+", modifierFlags: .command)
        XCTAssertTrue(poll { target.frame.width > width * 1.05 })
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(poll { abs(target.frame.width - width) < 2 })
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(page("Page handled K").waitForExistence(timeout: Self.renderTimeout), "Page-first shortcuts remain available to web apps")
        app.typeKey("s", modifierFlags: .command)
        target.hover()
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists })
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["sidebar.toggle"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("j", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("shortcuts-defaults", of: app)
    }

    func testZoomFeedbackShowsActualPercentageAndExpires() {
        open("shortcuts.html", expecting: "Shortcuts fixture")
        app.webViews.buttons["Zoom target"].click()
        let indicator = app.staticTexts["page.zoom"]
        XCTAssertFalse(indicator.exists)
        app.typeKey("+", modifierFlags: .command)
        XCTAssertTrue(indicator.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(indicator.value as? String, "110%")
        attachScreenshot("page-zoom-feedback", of: app)
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(poll { indicator.value as? String == "100%" })
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(poll { indicator.value as? String == "90%" })
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(poll { indicator.value as? String == "100%" })
        XCTAssertTrue(indicator.waitForNonExistence(timeout: 4))
        app.typeKey("+", modifierFlags: .command)
        XCTAssertTrue(indicator.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(indicator.waitForNonExistence(timeout: Self.renderTimeout))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(page("Shortcuts fixture").waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(indicator.exists, "Returning to a tab does not replay old zoom feedback")
    }

    func testCaptureConflictReplacePersistenceAndRestore() {
        openSettings("Shortcuts")
        search("Toggle sidebar")
        record("toggleSidebar", key: "q", modifiers: .command)
        XCTAssertFalse(app.buttons["shortcuts.save"].isEnabled, "Native Quit is protected")
        app.typeKey(.escape, modifierFlags: [])
        record("toggleSidebar", key: "t", modifiers: .command)
        XCTAssertTrue(app.staticTexts["shortcuts.conflict"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("shortcut-conflict", of: app)
        app.buttons["shortcuts.save"].click()
        closeSettings()
        app.typeKey("t", modifierFlags: .command)
        controlBarInput.hover()
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists }, "The replacement invokes sidebar, not New Tab")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.buttons["sidebar.toggle"].waitForExistence(timeout: Self.renderTimeout))

        relaunch()
        openSettings("Shortcuts")
        search("New tab")
        XCTAssertTrue(app.buttons["shortcuts.record.newTab"].value as? String == "None", "The displaced default stays disabled after launch")
        search("Toggle sidebar")
        shortcutSettings()
        app.menuItems["Disable shortcut"].click()
        XCTAssertTrue(app.buttons["shortcuts.record.toggleSidebar"].value as? String == "None")
        shortcutSettings()
        app.menuItems["Restore default"].click()
        closeSettings()
        app.typeKey("s", modifierFlags: .command)
        controlBarInput.hover()
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists })
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["sidebar.toggle"].waitForExistence(timeout: Self.renderTimeout))
    }

    func testUserOverrideWinsOverDefaultAndUnreadableDataIsPreserved() {
        app.terminate()
        seedPreferences(#"{"version":1,"overrides":{"toggleSidebar":[{"key":"t","modifiers":1}],"futureCommand":[]}}"#)
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.pageTimeout))
        openSettings("Shortcuts")
        search("New tab")
        XCTAssertTrue(app.staticTexts["shortcuts.blocked.newTab"].exists,
                      "A new default conflicting with a saved override is explained")
        attachScreenshot("shortcut-default-suppressed", of: app)
        search("Toggle sidebar")
        shortcutSettings()
        app.menuItems["Disable shortcut"].click()
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "en", locale: "en_US")
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.pageTimeout))
        openSettings("Shortcuts")
        search("Toggle sidebar")
        XCTAssertTrue(app.buttons["shortcuts.record.toggleSidebar"].value as? String == "None")

        app.terminate()
        seedPreferences("not a shortcut document")
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.pageTimeout))
        openSettings("Shortcuts")
        search("New tab")
        XCTAssertTrue(app.staticTexts["Saved shortcuts could not be read. Your data has been kept. Restore defaults to continue."].exists)
        XCTAssertFalse(app.buttons["shortcuts.record.newTab"].isEnabled)
        attachScreenshot("shortcuts-unreadable-preserved", of: app)
        app.buttons["shortcuts.restoreAll"].click()
        app.windows.buttons["Restore defaults"].firstMatch.click()
        XCTAssertTrue(app.buttons["shortcuts.record.newTab"].isEnabled)
    }

    func testOrderedTabsAndRecentTabsRemainDistinct() {
        open("solid.html", expecting: "Solid fixture")
        open("keys.html", expecting: "No shortcut yet")
        open("shortcuts.html", expecting: "Shortcuts fixture")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("9", modifierFlags: .command)
        XCTAssertTrue(page("Shortcuts fixture").waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(page("No shortcut yet").waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(page("Shortcuts fixture").waitForExistence(timeout: Self.renderTimeout), "Releasing Control commits MRU selection")
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.renderTimeout), "Shift reverses the recent-tab gesture")
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(page("Shortcuts fixture").waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("d", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(page("Shortcuts fixture").waitForExistence(timeout: Self.renderTimeout), "Numbered tabs follow favorites first")
        attachScreenshot("shortcuts-tab-order")
    }

    func testNativePrintReloadAndTabMenuActions() {
        open("solid.html", expecting: "Solid fixture")
        let requests = server.requests(for: "solid.html").count
        app.typeKey("r", modifierFlags: [.command, .shift])
        XCTAssertTrue(poll { self.server.requests(for: "solid.html").count > requests })
        app.typeKey("p", modifierFlags: .command)
        let cancel = app.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.pageTimeout), "WebKit opens a native print sheet")
        attachScreenshot("native-print-sheet", of: app)
        cancel.click()
        app.menuBars.menuBarItems["Tabs"].click()
        app.menuItems["Duplicate tab"].click()
        XCTAssertTrue(poll { self.tabRows.count == 2 })
        app.menuBars.menuBarItems["Tabs"].click()
        app.menuItems["Close other tabs"].click()
        XCTAssertTrue(poll { self.tabRows.count == 1 })
    }

    func testFrenchExpandedShortcutSettings() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR") + ["-NSDoubleLocalizedStrings", "YES", "-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"]
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.pageTimeout))
        openSettings()
        selectSettingsSection("Shortcuts")
        search("zoom")
        XCTAssertTrue(app.descendants(matching: .any)["shortcuts.command.zoomIn"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["shortcuts.command.resetZoom"].exists)
        attachScreenshot("shortcuts-french-expanded-rtl", of: app)
        shortcutSettings()
        attachScreenshot("shortcut-options-french-expanded-rtl", of: app)
        app.typeKey(.escape, modifierFlags: [])
    }

    func testSettingsNavigationAndWebsitePriority() {
        open("shortcuts.html", expecting: "Shortcuts fixture")
        openSettings("Shortcuts")
        let settings = app.windows.containing(.textField, identifier: "shortcuts.search").firstMatch
        XCTAssertEqual(settings.frame.width, 960, accuracy: 2)
        for identifier in [XCUIIdentifierMinimizeWindow, XCUIIdentifierZoomWindow, XCUIIdentifierFullScreenWindow] {
            let button = settings.buttons[identifier]
            XCTAssertTrue(!button.exists || !button.isEnabled)
        }
        XCTAssertTrue(settings.buttons[XCUIIdentifierCloseWindow].isEnabled)
        selectSettingsSection("Tabs")
        app.buttons["settings.back"].click()
        XCTAssertTrue(app.textFields["shortcuts.search"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(app.buttons["settings.forward"].isEnabled)
        selectSettingsSection("Profiles")
        XCTAssertFalse(app.buttons["settings.forward"].isEnabled, "New navigation discards forward history")
        selectSettingsSection("Shortcuts")
        attachScreenshot("settings-shortcut-catalog", of: app)
        search("Toggle sidebar")
        shortcutSettings()
        app.menuItems["Use website first"].click()
        attachScreenshot("settings-sidebar-shortcut-detail", of: app)
        closeSettings()
        app.webViews.buttons["Zoom target"].click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(page("Page handled S").waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(app.buttons["sidebar.toggle"].exists)
        relaunch()
        open("shortcuts.html", expecting: "Shortcuts fixture")
        app.webViews.buttons["Zoom target"].click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(page("Page handled S").waitForExistence(timeout: Self.renderTimeout), "Website priority survives relaunch")
        XCTAssertTrue(app.buttons["sidebar.toggle"].exists)
        // This fixture claims every Command key, including comma; use the native menu with page focus.
        app.menuBars.menuBarItems["Aero"].click()
        app.menuItems["Settings…"].click()
        selectSettingsSection("Shortcuts")
        search("Toggle sidebar")
        shortcutSettings()
        app.menuItems["Use Aero first"].click()
        closeSettings()
        app.webViews.buttons["Zoom target"].click()
        app.typeKey("s", modifierFlags: .command)
        app.webViews.buttons["Zoom target"].hover()
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists })
    }

    private func shortcutSettings() {
        app.descendants(matching: .any).matching(identifier: "shortcuts.settings").firstMatch.click()
    }

    private func search(_ text: String) {
        let field = app.textFields["shortcuts.search"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.renderTimeout))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func record(_ command: String, key: String, modifiers: XCUIElement.KeyModifierFlags) {
        app.buttons["shortcuts.record.\(command)"].click()
        XCTAssertTrue(app.buttons["shortcuts.save"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(key, modifierFlags: modifiers)
    }

    private func seedPreferences(_ json: String) {
        // NSArgumentDomain accepts property-list data. This reaches Aero's real preferences without
        // writing the runner container's unrelated UserDefaults or adding a production test hook.
        let data = Data(json.utf8).map { String(format: "%02x", $0) }.joined()
        app.launchArguments = TestApplication.launchArguments(language: "en", locale: "en_US") + ["-browser.shortcuts", "<" + data + ">"]
    }
}
