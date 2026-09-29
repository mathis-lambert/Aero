import XCTest

/// Who gets a shortcut while a page has focus, how tabs follow the keyboard, and recording shortcuts in Settings.
/// Resolution, conflicts and persistence are covered by ShortcutPreferencesTests. See docs/SHORTCUTS.md.
@MainActor
final class KeyboardJourneys: E2ETestCase {
    /// The selected tab, told by the page it shows.
    private func shows(_ text: String) -> Bool { page(text).waitForExistence(timeout: Self.renderTimeout) }

    /// Keys fixture's status names the last Command key it saw, which the shortcut itself changes.
    private var showsKeys: Bool {
        app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Page handled ⌘", "Page handled ⌘")).firstMatch.waitForExistence(timeout: Self.renderTimeout)
    }

    /// Pages that claim every Command key keep their page-first shortcuts, Aero keeps its reserved ones, zoom
    /// says what it did, and tabs follow sidebar order or recent use.
    func testPagesKeepTheirShortcutsAndAeroKeepsItsOwn() throws {
        try launch()
        open("shortcuts.html", expecting: "Shortcuts fixture")
        let editor = app.webViews.textFields["Editor"]
        editor.click()
        editor.typeText("été déjà vu")
        XCTAssertEqual(editor.value as? String, "été déjà vu", "Accented text never reaches the shortcut router")

        let target = app.webViews.buttons["Zoom target"], indicator = app.staticTexts["page.zoom"], width = target.frame.width
        target.click()
        app.typeKey("=", modifierFlags: .command)
        XCTAssertTrue(poll { target.frame.width > width * 1.05 }, "Command-equals zooms although the page claims every Command key")
        XCTAssertEqual(indicator.value as? String, "110%")
        attachScreenshot("zoom feedback")
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(poll { indicator.value as? String == "100%" && abs(target.frame.width - width) < 2 })
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(poll { indicator.value as? String == "90%" })
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(poll { indicator.value as? String == "100%" && abs(target.frame.width - width) < 2 })
        XCTAssertTrue(indicator.waitForNonExistence(timeout: 4), "The feedback expires")
        app.typeKey("+", modifierFlags: .command)
        XCTAssertTrue(indicator.waitForExistence(timeout: Self.renderTimeout), "Command-plus zooms too")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(indicator.waitForNonExistence(timeout: Self.renderTimeout))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(page("Shortcuts fixture").waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(indicator.exists, "Returning to a tab does not replay old feedback")

        target.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(page("Page handled K").waitForExistence(timeout: Self.renderTimeout), "Page-first shortcuts stay with web apps")
        app.typeKey("s", modifierFlags: .command)
        target.hover()
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists }, "Command-S stays with Aero")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["sidebar.toggle"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("j", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout), "Shift-Command-J shows downloads")
        app.typeKey(.escape, modifierFlags: [])

        open("keys.html", expecting: "No shortcut yet")
        app.webViews.firstMatch.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(page("Page handled ⌘K").waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(controlBarInput.exists, "Aero does not take a shortcut the page handled")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout), "⌘T stays with Aero")
        app.typeKey(.escape, modifierFlags: [])
        open("solid.html", expecting: "Solid fixture")
        app.webViews.firstMatch.click()
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout), "A page-first shortcut the page ignores reaches Aero")
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertEqual(labels(of: "sidebar.tab"), ["Shortcuts fixture", "Keys fixture", "Solid fixture"])
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(shows("Shortcuts fixture"))
        app.typeKey(.rightArrow, modifierFlags: [.command, .option])
        XCTAssertTrue(showsKeys, "Option-Command-Right follows sidebar order")
        app.typeKey("9", modifierFlags: .command)
        XCTAssertTrue(shows("Solid fixture"), "Command-9 selects the last tab")
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(showsKeys, "Control-Tab goes back to the most recent tab")
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(shows("Solid fixture"), "Releasing Control committed the previous choice")
        app.typeKey(.tab, modifierFlags: [.control, .shift])
        XCTAssertTrue(shows("Shortcuts fixture"), "Shift reverses the recent-tab order")
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(shows("Solid fixture"))
        app.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(poll { self.labels(of: "sidebar.tile") == ["Solid fixture"] }, "Command-D adds the tab to favorites")
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout), "Numbered tabs count favorites first")
        attachScreenshot("tab order")
    }

    /// Recording replaces a conflicting shortcut, restoring brings the default back, and a shortcut can be left to
    /// the website or kept by Aero. Settings is a fixed-size window with its own back and forward.
    func testShortcutSettingsRecordAndGivePriority() throws {
        try launch()
        open("shortcuts.html", expecting: "Shortcuts fixture")
        openSettings("Shortcuts")
        let settings = app.windows.containing(.textField, identifier: "shortcuts.search").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(settings.frame.width, 960, accuracy: 2)
        for identifier in [XCUIIdentifierMinimizeWindow, XCUIIdentifierZoomWindow, XCUIIdentifierFullScreenWindow] {
            XCTAssertFalse(settings.buttons[identifier].exists && settings.buttons[identifier].isEnabled, "Settings cannot \(identifier)")
        }
        selectSettingsSection("Tabs")
        app.buttons["settings.back"].click()
        XCTAssertTrue(app.textFields["shortcuts.search"].waitForExistence(timeout: Self.renderTimeout), "Back returns to Shortcuts")
        XCTAssertTrue(app.buttons["settings.forward"].isEnabled)
        selectSettingsSection("Profiles")
        XCTAssertFalse(app.buttons["settings.forward"].isEnabled, "New navigation discards forward history")
        selectSettingsSection("Shortcuts")
        attachScreenshot("shortcut catalog", of: app)

        search("Toggle Sidebar")
        app.buttons["shortcuts.record.toggleSidebar"].click()
        XCTAssertTrue(app.buttons["shortcuts.save"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["shortcuts.conflict"].waitForExistence(timeout: Self.renderTimeout), "The recorder names the conflict")
        attachScreenshot("shortcut conflict", of: app)
        app.buttons["shortcuts.save"].click()
        search("New Tab")
        XCTAssertEqual(app.buttons["shortcuts.record.newTab"].value as? String, "None", "The displaced command loses its shortcut")
        closeSettings()
        app.webViews.buttons["Zoom target"].click()
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists }, "Command-T now toggles the sidebar")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(app.buttons["sidebar.toggle"].waitForExistence(timeout: Self.renderTimeout))

        openSettings("Shortcuts")
        search("Toggle Sidebar")
        shortcutOptions("Restore default")
        shortcutOptions("Use website first")
        attachScreenshot("shortcut priority", of: app)
        closeSettings()
        app.webViews.buttons["Zoom target"].click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(page("Page handled S").waitForExistence(timeout: Self.renderTimeout), "The website gets it first")
        XCTAssertTrue(app.buttons["sidebar.toggle"].exists)

        // The page claims every Command key, comma included; openSettings uses the menu bar.
        openSettings("Shortcuts")
        search("Toggle Sidebar")
        shortcutOptions("Use Aero first")
        closeSettings()
        app.webViews.buttons["Zoom target"].click()
        app.typeKey("s", modifierFlags: .command)
        app.webViews.buttons["Zoom target"].hover()
        XCTAssertTrue(poll { !self.app.buttons["sidebar.toggle"].exists }, "Aero gets it first again")
    }

    private func search(_ text: String) { replaceText(of: app.textFields["shortcuts.search"], with: text) }

    private func shortcutOptions(_ item: String) {
        element("shortcuts.settings").click()
        app.menuItems[item].click()
    }
}
