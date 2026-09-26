import XCTest

/// The control bar on the New Tab page and over tabs. See docs/CONTROL_BAR.md.
@MainActor
final class ControlBarE2ETests: BrowserE2ETestCase {
    private static let item = "controlBar.item"
    private static let suggestions = "suggest.json"
    /// Longer than the pause the bar waits for before requesting suggestions.
    private static let typingPause: TimeInterval = 1.5

    private var controlBarInputs: XCUIElementQuery { app.textFields.matching(identifier: "controlBar.input") }
    private var items: [String] { labels(of: Self.item) }

    func testSuggestionsSearchWithTheChosenEngine() {
        setSearchEngine("Google")
        controlBarInput.click()
        controlBarInput.typeText("aero")
        XCTAssertTrue(poll { self.items.starts(with: ["aero", "aero browser", "aero macos"]) }, "The search first, then the engine's suggestions")
        let request = server.requests(for: Self.suggestions).last
        XCTAssertEqual(request?.queryItems?.first { $0.name == "engine" }?.value, "google")
        attachScreenshot("control-bar-suggestions")

        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.labels(of: "sidebar.tab") == ["google: aero browser"] },
                      "The highlighted suggestion is searched with the chosen engine")

        relaunch()
        openSettings()
        XCTAssertEqual(app.popUpButtons["settings.searchEngine"].value as? String, "Google", "The engine survives a relaunch")
    }

    func testSuggestionsAreNeverRequestedForAddressesOrWhenOff() {
        controlBarInput.click()
        controlBarInput.typeText(server.url("solid.html").absoluteString)
        pause(Self.typingPause)
        XCTAssertTrue(server.requests(for: Self.suggestions).isEmpty, "An address is never sent to the engine")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        openSettings()
        app.checkBoxes["settings.searchSuggestions"].click()
        app.buttons["settings.close"].click()
        controlBarInput.click()
        controlBarInput.typeText("aero")
        pause(Self.typingPause)
        XCTAssertTrue(server.requests(for: Self.suggestions).isEmpty, "Nothing is sent while suggestions are off")
        XCTAssertEqual(items, ["aero"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.labels(of: "sidebar.tab") == ["google: aero"] },
                      "Searches use Google by default")
    }

    func testLocationReplacesThePageAndThePaletteOpensATab() {
        open("history-lake.html", expecting: "Alpine Lake fixture")
        let lake = server.url("history-lake.html").absoluteString
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        // The New Tab page's bar may still be leaving the hierarchy for a moment.
        XCTAssertTrue(poll { self.controlBarInput.value as? String == lake }, "⌘L starts from the page's address")
        controlBarInput.typeText(server.url("solid.html").absoluteString + "\n")
        XCTAssertTrue(app.webViews.staticTexts["Solid fixture"].waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 1, "⌘L replaces the page in its tab")

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(controlBarInput.value as? String ?? "", "")
        controlBarInput.typeText(server.url("history-city.html").absoluteString + "\n")
        XCTAssertTrue(app.webViews.staticTexts["Été à Lyon fixture"].waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 2, "⌘K opens its result in a new tab")

        app.typeKey("k", modifierFlags: .command)
        controlBarInput.typeText("alpine")
        XCTAssertTrue(poll { self.items.contains("Alpine Lake") }, "History matches the words of a visited page")
        app.typeKey("a", modifierFlags: .command)
        controlBarInput.typeText("Solid")
        XCTAssertTrue(poll { self.items.contains("Solid fixture") }, "An open tab matches its title")
        itemButton("Solid fixture").click()
        XCTAssertFalse(controlBarInput.exists)
        XCTAssertEqual(tabRows.count, 2, "Choosing an open tab switches to it")
        XCTAssertTrue(app.webViews.staticTexts["Solid fixture"].waitForExistence(timeout: Self.pageTimeout))

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(controlBarInput.exists, "Escape closes the bar over a tab")
    }

    func testCommandsAreListedAndRunLikeTheirMenus() {
        open("solid.html", expecting: "Solid fixture")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(poll { self.items.contains("Show all history") && self.items.contains("New tab") },
                      "With no text, the bar lists the commands")
        attachScreenshot("control-bar-commands")
        controlBarInput.typeText("history")
        XCTAssertTrue(poll { self.items.contains("Show all history") })
        itemButton("Show all history").click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab").last == "History" }, "The command opens History, like its menu item")
        XCTAssertFalse(controlBarInput.exists)
    }

    func testNewTabShortcutsFocusThePageBar() {
        attachScreenshot("new-tab")
        for key in ["k", "l"] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertEqual(controlBarInputs.count, 1, "⌘\(key.uppercased()) focuses the New Tab bar instead of opening another")
        }
        controlBarInput.typeText("aero")
        XCTAssertEqual(controlBarInput.value as? String, "aero")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(controlBarInput.value as? String ?? "", "", "Escape clears the New Tab bar")
    }

    private func itemButton(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: Self.item).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func openSettings() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.popUpButtons["settings.searchEngine"].waitForExistence(timeout: Self.renderTimeout))
    }

    private func setSearchEngine(_ name: String) {
        openSettings()
        app.popUpButtons["settings.searchEngine"].click()
        app.menuItems[name].click()
        app.buttons["settings.close"].click()
    }

    private func pause(_ seconds: TimeInterval) {
        RunLoop.current.run(until: .now.addingTimeInterval(seconds))
    }
}
