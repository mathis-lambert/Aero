import XCTest

/// The first launch and later imports, on the fixture browsers in `Fixtures/import-sources`. The formats themselves
/// (Arc, Chromium, Dia, Safari) are covered by BrowserStorageTests. See docs/ONBOARDING.md › Verification.
@MainActor
final class OnboardingJourneys: E2ETestCase {
    /// First-launch window sizing must settle before interaction and restore browser sizing on exit.
    /// Conflicting AppKit and SwiftUI constraints can abort in the first display cycle.
    func testFirstLaunchWindowSettlesThenRestoresBrowser() throws {
        try launch(Launch(french: true, screen: .onboarding))
        XCTAssertFalse(app.buttons["sidebar.toggle"].exists, "The browser is not created behind first-launch onboarding")
        let window = app.windows.firstMatch
        XCTAssertTrue(poll {
            abs(window.frame.width - 1040) < 2 && (660...700).contains(window.frame.height)
        }, "The onboarding settles at its compact size: \(window.frame)")
        // Window accessibility frames include the native title bar, whose height is system-owned.
        let compactHeight = window.frame.height
        attachScreenshot("first visible screen is onboarding")
        app.buttons["onboarding.start"].click()
        XCTAssertTrue(app.buttons["onboarding.source.Google Chrome"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["sidebar.toggle"].exists)
        XCTAssertEqual(window.frame.width, 1040, accuracy: 2)
        XCTAssertEqual(window.frame.height, compactHeight, accuracy: 2)
        attachScreenshot("first launch compact window")
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(poll { !self.app.groups["onboarding"].exists && window.frame.width > 1040 })
        XCTAssertTrue(app.buttons["sidebar.toggle"].isHittable)
        attachScreenshot("browser window after first launch")
    }

    private var title: String { element("onboarding.title").label }
    private var continueButton: XCUIElement { app.buttons["onboarding.continue"] }

    private func shortcut(_ label: String) -> XCUIElement {
        app.buttons.matching(identifier: "onboarding.shortcut").matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    private func waitForTitle(_ expected: String, timeout: TimeInterval = pageTimeout) {
        XCTAssertTrue(poll(timeout: timeout) { self.title == expected }, "The step reads “\(expected)”, not “\(self.title)”")
    }

    /// Failure modes 1, 2, 4, 9 and 12: from the keyboard, Arc's spaces, favorites and folders arrive in their
    /// profiles and open tabs do not; a relaunch resumes the step; the Back command goes back; the shortcuts taught
    /// are tried in place; completion is remembered.
    func testArcImportFromTheKeyboardLandsInTheBrowser() throws {
        try launch(Launch(screen: .onboarding))
        XCTAssertTrue(app.buttons["window.close"].isHittable, "The window controls stay on the onboarding")
        attachScreenshot("1 welcome")

        app.typeKey(.return, modifierFlags: [])
        let chrome = app.buttons["onboarding.source.Google Chrome"], arc = app.buttons["onboarding.source.Arc"]
        XCTAssertTrue(chrome.waitForExistence(timeout: Self.renderTimeout), "Return starts")
        XCTAssertTrue(app.buttons["onboarding.source.Dia"].exists && app.buttons["onboarding.source.Safari"].exists)
        XCTAssertTrue(poll { chrome.isSelected })
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll { arc.isSelected && !chrome.isSelected }, "Down chooses the next browser")

        relaunch()
        XCTAssertTrue(arc.waitForExistence(timeout: Self.renderTimeout), "A relaunch resumes on the source step")
        arc.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.continueButton.isEnabled }, "Arc is read")
        attachScreenshot("2 source")
        app.typeKey(.return, modifierFlags: [])
        waitForTitle("Choose what to bring.")
        // The Back command, from its menu item: the test Mac's layout may not type Command-Left Bracket.
        chooseInMenuBar("History", "Back")
        XCTAssertTrue(poll { arc.exists && arc.isSelected }, "Back goes to the previous step, keeping the choice")
        app.typeKey(.return, modifierFlags: [])
        waitForTitle("Choose what to bring.")
        attachScreenshot("3 choice")
        app.typeKey(.return, modifierFlags: [])
        waitForTitle("Everything is here.")
        attachScreenshot("4 import")
        app.typeKey(.return, modifierFlags: [])
        waitForTitle("Within reach.")

        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(poll { self.shortcut("last tab").isSelected }, "Control-Tab is tried in place")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(poll { self.shortcut("control bar").isSelected }, "Command-K is tried in place")
        app.typeKey(.rightArrow, modifierFlags: [.control, .command])
        attachScreenshot("5 getting around")
        app.typeKey(.return, modifierFlags: [])
        // Never change the Mac's default browser from a test: Return here would ask macOS.
        XCTAssertTrue(app.buttons["onboarding.makeDefault"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("6 default browser")
        app.buttons["onboarding.notNow"].click()
        waitForTitle("Fair winds.")
        attachScreenshot("7 ready")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "Return starts browsing")

        XCTAssertTrue(poll { self.app.buttons["window.close"].isHittable }, "The window controls are back in the sidebar")
        // The window is still expanding; two accessibility queries can sample different animation frames.
        XCTAssertTrue(poll {
            abs(self.app.buttons["window.close"].frame.midY - self.app.buttons["sidebar.toggle"].frame.midY) <= 0.5
        }, "The window controls settle into alignment with the sidebar")
        attachScreenshot("8 browser")
        XCTAssertEqual(labels(of: "sidebar.space"), ["Personal", "Work", "Studio"], "Arc's spaces, in order")
        XCTAssertTrue(labels(of: "sidebar.tab").isEmpty, "No open tab is imported, and Control-Tab switched nothing behind")
        // Getting around switched spaces for real; Reading is in Personal.
        space("Personal").click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.group") == ["Reading"] }, "The Long reads subfolder is gathered in Reading")
        let favorites = labels(of: "sidebar.favorite") + labels(of: "sidebar.tile")
        XCTAssertFalse(favorites.isEmpty, "Imported favorites are in the sidebar")
        XCTAssertFalse(favorites.contains { $0.contains("Open tab") }, "Open tabs are never imported: \(favorites)")

        relaunch { $0.screen = .browser }
        XCTAssertFalse(app.groups["onboarding"].exists, "Completion is remembered")
    }

    /// Failure mode 13 and dark paper: every step fits in French. Chrome's profile becomes a space whose bookmarks
    /// bar gives favorites and whose first-level folders give groups, with Chrome's own icons; Skip ends it for good.
    func testChromeImportInFrenchAndDarkThenSkip() throws {
        try launch(Launch(french: true, dark: true, screen: .onboarding))
        attachScreenshot("fr dark 1 welcome")
        app.buttons["onboarding.start"].click()
        app.buttons["onboarding.source.Google Chrome"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.continueButton.isEnabled })
        attachScreenshot("fr dark 2 source")
        continueButton.click()
        waitForTitle("Choisissez quoi importer.")
        attachScreenshot("fr dark 3 choice")
        continueButton.click()
        waitForTitle("Tout est là.")
        attachScreenshot("fr dark 4 import")
        continueButton.click()
        waitForTitle("À portée de main.")
        attachScreenshot("fr dark 5 getting around")
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "Skip ends the onboarding")

        XCTAssertEqual(labels(of: "sidebar.space"), ["Home"])
        XCTAssertTrue(labels(of: "sidebar.favorite").contains("Weather"), "The bookmarks bar is in the sidebar")
        let groups = labels(of: "sidebar.group")
        XCTAssertEqual(groups.count, 3, "First-level folders only: \(groups)")
        XCTAssertEqual(Array(groups.prefix(2)), ["Recipes", "Recipes"], "Two folders with one name stay two")
        // The two groups share their name: open each until the one holding the Winter subfolder shows it.
        let gathered = { ["Soup", "Stew"].allSatisfy(self.labels(of: "sidebar.favorite").contains) }
        for index in 0..<2 where !gathered() {
            groupHeaders.matching(NSPredicate(format: "label == %@", "Recipes")).element(boundBy: index).click()
            _ = poll(timeout: 2, gathered)
        }
        XCTAssertTrue(gathered(), "The Winter subfolder is gathered in Recipes")
        attachScreenshot("fr dark 6 browser")
        let icons = FileManager.default.enumerator(atPath: dataRoot.appendingPathComponent("Caches/Favicons").path)
        XCTAssertTrue((icons?.allObjects as? [String] ?? []).contains { $0.hasSuffix("weather.test.png") }, "Chrome's icon for Weather is Aero's")

        relaunch { $0.screen = .browser }
        XCTAssertFalse(app.groups["onboarding"].exists, "Skip is remembered")
    }

    /// docs/ONBOARDING.md › When it appears and failure mode 2: someone already browsing imports from the File
    /// menu, Escape cancels, and importing again adds nothing twice.
    func testImportingAgainAddsNothingTwice() throws {
        try launch()
        chooseInMenuBar("File", "Import from Another Browser…")
        XCTAssertTrue(app.buttons["onboarding.source.Google Chrome"].waitForExistence(timeout: Self.renderTimeout), "The import steps open")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "Escape cancels")

        importChrome()
        let spaces = labels(of: "sidebar.space"), groups = labels(of: "sidebar.group")
        let favorites = labels(of: "sidebar.favorite") + labels(of: "sidebar.tile")
        XCTAssertFalse(favorites.isEmpty, "Chrome's bookmarks bar is in the sidebar")
        importChrome()
        XCTAssertEqual(labels(of: "sidebar.space"), spaces, "No space added twice")
        XCTAssertEqual(labels(of: "sidebar.group"), groups, "No group added twice, even two with the same name")
        XCTAssertEqual(labels(of: "sidebar.favorite") + labels(of: "sidebar.tile"), favorites, "No favorite added twice")
        attachScreenshot("after the second import")
    }

    private func importChrome() {
        chooseInMenuBar("File", "Import from Another Browser…")
        let chrome = app.buttons["onboarding.source.Google Chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: Self.renderTimeout))
        chrome.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.continueButton.isEnabled })
        continueButton.click()
        continueButton.click()
        waitForTitle("Everything is here.")
        continueButton.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "Done closes the import")
    }
}
