import AppKit
import XCTest

/// Getting to pages and using them: the control bar, New Tab, popups, find, downloads and the page's own features.
/// See docs/BROWSING.md.
@MainActor
final class BrowsingJourneys: E2ETestCase {
    private static let orange = ScreenshotColor(red: 255, green: 90, blue: 0)
    private static let blue = ScreenshotColor(red: 30, green: 64, blue: 255)
    /// Center of the leading icon in a tab row: 10 pt padding plus half of the 18 pt icon frame.
    private static let tabIconCenterX: CGFloat = 19

    private var items: [String] { labels(of: "controlBar.item") }
    private func item(_ label: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: "controlBar.item")[label] }

    /// New Tab is one permanent row whose bar ⌘K and ⌘L focus; over a tab, ⌘L replaces its page, ⌘K opens a new
    /// tab, and the bar finds history, open tabs and commands.
    func testTheControlBarOpensSearchesAndSwitches() throws {
        try launch()
        let newTab = app.buttons["sidebar.newTab"]
        XCTAssertTrue(newTab.isSelected)
        for key in ["k", "l"] {
            app.typeKey(key, modifierFlags: .command)
            XCTAssertEqual(app.textFields.matching(identifier: "controlBar.input").count, 1, "⌘\(key.uppercased()) focuses the New Tab bar")
        }
        controlBarInput.typeText("aero")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(controlBarInput.value as? String ?? "", "", "Escape clears the New Tab bar")
        attachScreenshot("new tab")

        open("history-lake.html", expecting: "Alpine Lake fixture")
        XCTAssertFalse(newTab.isSelected)
        XCTAssertLessThan(newTab.frame.maxY, tabRows.firstMatch.frame.minY, "New Tab stays above the open tabs")
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        // The New Tab page's bar may still be leaving the hierarchy for a moment.
        XCTAssertTrue(poll { self.controlBarInput.value as? String == self.server.url("history-lake.html").absoluteString }, "⌘L starts from the page's address")
        controlBarInput.typeText(server.url("solid.html").absoluteString + "\n")
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 1, "⌘L replaces the page in its tab")
        let webView = app.webViews.firstMatch
        XCTAssertTrue(poll { Self.blue.isShown(in: webView, at: CGPoint(x: webView.frame.width / 2, y: webView.frame.height / 2)) },
                      "The page becomes visible after its first frame")

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(poll { self.items.contains("Show All History") && self.items.contains("New Tab") }, "With no text, the bar lists the commands")
        attachScreenshot("control bar commands")
        controlBarInput.typeText(server.url("history-city.html").absoluteString + "\n")
        XCTAssertTrue(page("Été à Lyon fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 2, "⌘K opens its result in a new tab")

        app.typeKey("k", modifierFlags: .command)
        controlBarInput.typeText("alpine")
        XCTAssertTrue(poll { self.items.contains("Alpine Lake") }, "History matches the words of a visited page")
        app.typeKey("a", modifierFlags: .command)
        controlBarInput.typeText("Solid")
        XCTAssertTrue(poll { self.items.contains("Solid fixture") }, "An open tab matches its title")
        item("Solid fixture").click()
        XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 2, "Choosing an open tab switches to it")

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(controlBarInput.exists, "Escape closes the bar over a tab")

        runCommand("Show All History")
        XCTAssertTrue(poll { self.labels(of: "sidebar.tab").last == "History" }, "The command opens History, like its menu item")
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(poll { newTab.isSelected })
        XCTAssertEqual(app.buttons.matching(identifier: "sidebar.newTab").count, 1, "New Tab stays one row")
        XCTAssertEqual(tabRows.count, 3, "⌘T adds no row")
    }

    /// The suggestions come from the chosen engine and never see an address or anything while turned off; local
    /// history never waits for a slow engine, and a cancelled query cannot bring old results back.
    func testSuggestionsFollowTheEngineAndStayPrivate() throws {
        try launch()
        controlBarInput.click()
        controlBarInput.typeText(server.url("solid.html").absoluteString)
        pause(1.5) // Longer than the pause the bar waits for before asking.
        XCTAssertTrue(server.requests(for: "suggest.json").isEmpty, "An address is never sent to the engine")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        controlBarInput.typeText("aero")
        XCTAssertTrue(poll { self.items.starts(with: ["aero", "aero browser", "aero macos"]) }, "The search first, then the engine's suggestions")
        XCTAssertEqual(server.requests(for: "suggest.json").last?.queryItems?.first { $0.name == "engine" }?.value, "google", "Google by default")
        attachScreenshot("suggestions")
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.labels(of: "sidebar.tab") == ["google: aero browser"] },
                      "The highlighted suggestion is searched with the engine")

        open("history-lake.html", expecting: "Alpine Lake fixture")
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("t", modifierFlags: .command)
        server.delaySuggestions(by: 2.5)
        controlBarInput.click()
        controlBarInput.typeText("alpine")
        XCTAssertTrue(poll(timeout: 1.5) { self.items.contains("Alpine Lake") }, "Local history appears before the delayed engine")
        app.typeKey("a", modifierFlags: .command)
        controlBarInput.typeText("zzzz")
        XCTAssertTrue(poll { !self.items.contains("Alpine Lake") })
        pause(3)
        XCTAssertFalse(items.contains("Alpine Lake"), "A cancelled query cannot republish old history")
        server.delaySuggestions(by: 0)
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])

        openSettings("General")
        app.switches["settings.searchSuggestions"].click()
        closeSettings()
        let asked = server.requests(for: "suggest.json").count
        controlBarInput.click()
        controlBarInput.typeText("aero")
        pause(1.5)
        XCTAssertEqual(server.requests(for: "suggest.json").count, asked, "Nothing is sent while suggestions are off")
        XCTAssertFalse(items.contains("aero browser"), "…so none are shown: \(items)")
    }

    /// What a page does with the browser: its icon, popups that talk back, find, downloads, printing, reloading
    /// from the server, and pages that try to open Aero's own.
    func testPagesUseTheirBrowserFeatures() throws {
        try launch()
        open("favicon.html", expecting: "Favicon fixture")
        let row = tabRows.firstMatch
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { Self.orange.isShown(in: row, at: CGPoint(x: Self.tabIconCenterX, y: row.frame.height / 2)) },
                      "The declared favicon is shown in the tab row")

        open("popup-opener.html", expecting: "Waiting for popup")
        app.webViews.buttons["Open popup"].click()
        XCTAssertTrue(page("Popup fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(tabRows.count, 3, "The popup opens as a tab")
        app.webViews.buttons["Close popup"].click()
        XCTAssertTrue(page("Opener received message").waitForExistence(timeout: Self.pageTimeout), "The opener got the popup's message and is selected again")
        XCTAssertEqual(tabRows.count, 2, "window.close() closes the popup tab")

        open("find.html", expecting: "Nothing selected")
        app.typeKey("f", modifierFlags: .command)
        let field = app.textFields["find.input"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.renderTimeout))
        field.typeText("needle")
        XCTAssertTrue(page("Selected needle").waitForExistence(timeout: Self.renderTimeout), "The first match is selected")
        attachScreenshot("find")
        field.typeText("zzz")
        XCTAssertTrue(app.staticTexts["find.noMatches"].waitForExistence(timeout: Self.renderTimeout), "A miss is reported")
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(field.waitForExistence(timeout: 1), "Escape closes the bar")

        open("downloads.html", expecting: "Download report")
        app.buttons["downloads.button"].click()
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout), "The popover says there are none yet")
        app.typeKey(.escape, modifierFlags: [])
        app.webViews.links["Download report"].click()
        app.buttons["downloads.button"].click()
        XCTAssertTrue(app.staticTexts["report.csv"].waitForExistence(timeout: Self.pageTimeout), "The download appears")
        XCTAssertTrue(app.buttons["downloads.reveal"].waitForExistence(timeout: Self.pageTimeout), "The download finishes")
        XCTAssertFalse(app.staticTexts["This page could not be opened"].exists, "The page that started it stays displayed")
        attachScreenshot("download")
        app.buttons["downloads.clear"].click()
        XCTAssertTrue(app.staticTexts["downloads.empty"].waitForExistence(timeout: Self.renderTimeout), "Clearing removes finished downloads")
        app.typeKey(.escape, modifierFlags: [])

        let requests = server.requests(for: "downloads.html").count
        app.typeKey("r", modifierFlags: [.command, .shift])
        XCTAssertTrue(poll { self.server.requests(for: "downloads.html").count > requests }, "Reloading without cache asks the server again")
        app.typeKey("p", modifierFlags: .command)
        let cancel = app.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: Self.pageTimeout), "WebKit opens the native print sheet")
        cancel.click()

        NSPasteboard.general.clearContents()
        app.buttons["address.copyLink"].click()
        XCTAssertTrue(poll { NSPasteboard.general.string(forType: .string) == self.server.url("downloads.html").absoluteString },
                      "Copy Link puts the page's address on the pasteboard")

        open("internal-link.html", expecting: "Open history")
        app.webViews.links["Open history"].click()
        XCTAssertFalse(app.textFields["history.search"].waitForExistence(timeout: 2), "A page cannot navigate to aero://history")
        XCTAssertFalse(labels(of: "sidebar.tab").contains("History"))
    }
}
