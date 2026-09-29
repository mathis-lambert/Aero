import XCTest

/// docs/ONBOARDING.md › Verification: the first launch on fixture browsers, with a screenshot of every step.
@MainActor
final class OnboardingE2ETests: BrowserE2ETestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        server = try FixtureServer()
        app = TestApplication.make()
        app.launchEnvironment["AERO_TEST_ONBOARDING"] = "1"
        app.launchEnvironment["AERO_TEST_IMPORT_SOURCES"] = Self.fixtures.appendingPathComponent("import-sources").path
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: TestApplication.launchTimeout), "the onboarding opens a fresh store")
    }

    private var continueButton: XCUIElement { app.buttons["onboarding.continue"] }

    private func next(_ screenshot: String) {
        attachScreenshot(screenshot)
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.continueButton.isEnabled }, "\(screenshot) can continue")
        continueButton.click()
    }

    /// Failure modes 1, 2, 4, 9 and 12: Arc's spaces, favorites and folders arrive in their profiles, open tabs do
    /// not, a second launch starts on the browser.
    func testArcImportWalksEveryStepAndLandsInTheBrowser() {
        // The wind gathers into the letter.
        pause(3)
        attachScreenshot("1 welcome")
        app.buttons["onboarding.start"].click()

        let arc = app.buttons["onboarding.source.Arc"]
        XCTAssertTrue(arc.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(app.buttons["onboarding.source.Google Chrome"].exists)
        XCTAssertTrue(app.buttons["onboarding.source.Dia"].exists)
        XCTAssertTrue(app.buttons["onboarding.source.Safari"].exists)
        arc.click()
        pause(2)
        next("2 source")

        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Choose what to bring." })
        pause(2)
        next("3 choice")

        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Everything is here." },
                      "the import finishes")
        pause(2)
        next("4 import")

        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Within reach." })
        app.typeKey(.rightArrow, modifierFlags: [.control, .command])
        pause(1.5)
        attachScreenshot("6b getting around after switching")
        next("6 getting around")

        // Never change the Mac's default browser from a test.
        attachScreenshot("7 default browser")
        app.buttons["onboarding.notNow"].click()

        pause(2)
        attachScreenshot("8 ready")
        continueButton.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "the onboarding ends")
        pause(1.5)
        attachScreenshot("9 browser")
        XCTAssertTrue(app.buttons["window.close"].isHittable, "the window controls are back in the sidebar")
        XCTAssertEqual(app.buttons["window.close"].frame.midY, app.buttons["sidebar.toggle"].frame.midY, accuracy: 0.5)

        XCTAssertEqual(labels(of: "sidebar.space"), ["Personal", "Work", "Studio"], "Arc's spaces, in order")
        // Getting around switched spaces; Reading is in Personal.
        space("Personal").click()
        XCTAssertTrue(poll { self.labels(of: "sidebar.group") == ["Reading"] }, "the Long reads subfolder is gathered in Reading")
        let favorites = labels(of: "sidebar.favorite") + labels(of: "sidebar.tile")
        XCTAssertFalse(favorites.isEmpty, "imported favorites are in the sidebar")
        XCTAssertFalse(favorites.contains { $0.contains("Open tab") }, "open tabs are never imported: \(favorites)")

        relaunch()
        XCTAssertFalse(app.groups["onboarding"].waitForExistence(timeout: 2), "completion is remembered")
    }

    /// Failure mode 1: a relaunch mid-onboarding resumes on the same step.
    func testRelaunchResumesOnTheSameStep() {
        app.buttons["onboarding.start"].click()
        XCTAssertTrue(app.buttons["onboarding.source.Arc"].waitForExistence(timeout: Self.renderTimeout))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.source.Arc"].waitForExistence(timeout: TestApplication.launchTimeout), "back on the source step")
        attachScreenshot("resumed on source")
    }

    /// Starting fresh skips the import; Skip ends it for good.
    func testStartFreshAndSkip() {
        XCTAssertTrue(app.buttons["window.close"].isHittable)
        app.buttons["onboarding.start"].click()
        app.buttons["onboarding.source.fresh"].click()
        continueButton.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Within reach." },
                      "fresh goes past the import")
        attachScreenshot("fresh getting around")
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists })
        // The window grows back to a browser first.
        XCTAssertTrue(poll { self.app.buttons["window.close"].isHittable })
        XCTAssertEqual(app.buttons["window.close"].frame.midY, app.buttons["sidebar.toggle"].frame.midY, accuracy: 0.5)
        app.buttons["window.close"].hover()
        attachScreenshot("window-controls-after-onboarding", of: app)
        relaunch()
        XCTAssertFalse(app.groups["onboarding"].waitForExistence(timeout: 2))
    }
}

extension OnboardingE2ETests {
    /// Imports from `source`, skips the rest, and returns the browser's spaces.
    private func importFrom(_ source: String, screenshot: String) -> [String] {
        app.buttons["onboarding.start"].click()
        let row = app.buttons["onboarding.source.\(source)"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout))
        row.click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.buttons["onboarding.continue"].isEnabled }, "\(source) is read")
        attachScreenshot("\(screenshot) source")
        app.buttons["onboarding.continue"].click()
        pause(1.5)
        attachScreenshot("\(screenshot) choice")
        app.buttons["onboarding.continue"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Everything is here." })
        attachScreenshot("\(screenshot) import")
        app.buttons["onboarding.continue"].click()
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists })
        pause(1)
        attachScreenshot("\(screenshot) browser")
        return labels(of: "sidebar.space")
    }

    /// Each Chrome profile becomes a space: the bookmarks bar gives favorites, each first-level folder a group that
    /// gathers its subfolders, and Chrome's own icons come along.
    func testChromeProfilesBecomeSpaces() throws {
        XCTAssertEqual(importFrom("Google Chrome", screenshot: "chrome"), ["Home"])
        XCTAssertTrue(labels(of: "sidebar.favorite").contains("Weather"), "the bookmarks bar is in the sidebar")
        XCTAssertEqual(labels(of: "sidebar.group"), ["Recipes", "Recipes", "Other bookmarks"],
                       "first-level folders only, never flattened into one; two folders with one name stay two")
        app.buttons.matching(identifier: "sidebar.group").matching(NSPredicate(format: "label == %@", "Recipes")).firstMatch.click()
        XCTAssertTrue(poll { ["Soup", "Stew"].allSatisfy(self.labels(of: "sidebar.favorite").contains) }, "the Winter subfolder is gathered in Recipes")
        attachScreenshot("chrome groups")
        let root = try XCTUnwrap(app.launchEnvironment[TestApplication.testDataKey])
        let icons = FileManager.default.enumerator(atPath: URL(fileURLWithPath: root).appendingPathComponent("Caches/Favicons").path)
        XCTAssertTrue((icons?.allObjects as? [String] ?? []).contains { $0.hasSuffix("weather.test.png") }, "Chrome's icon for Weather is Aero's")
    }

    /// Dia encrypts its spaces and favorites: the onboarding says so, and each Dia profile becomes an empty space with
    /// its history; the leftovers of its Bookmarks file are not taken for favorites.
    func testDiaProfilesBecomeSpacesWithoutFavorites() {
        app.buttons["onboarding.start"].click()
        app.buttons["onboarding.source.Dia"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.buttons["onboarding.continue"].isEnabled })
        app.buttons["onboarding.continue"].click()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.encrypted"].waitForExistence(timeout: Self.renderTimeout), "Dia's encryption is said")
        attachScreenshot("dia choice")
        app.buttons["onboarding.continue"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Everything is here." })
        attachScreenshot("dia import")
        app.buttons["onboarding.continue"].click()
        app.buttons["onboarding.skip"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists })
        XCTAssertEqual(labels(of: "sidebar.space").sorted(), ["Boulot", "Perso"])
        XCTAssertTrue(labels(of: "sidebar.favorite").isEmpty && labels(of: "sidebar.tile").isEmpty, "no favorites")
        attachScreenshot("dia browser")
    }

    /// Safari's favorites bar and menu arrive in one space.
    func testSafariFavoritesArrive() {
        XCTAssertEqual(importFrom("Safari", screenshot: "safari"), ["Safari"])
    }
}

extension OnboardingE2ETests {
    /// Failure mode 13: French runs longer; every step still fits its plate.
    func testFrenchFitsEveryStep() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: TestApplication.launchTimeout))
        pause(2.5)
        attachScreenshot("fr 1 welcome")
        app.buttons["onboarding.start"].click()
        app.buttons["onboarding.source.Arc"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.buttons["onboarding.continue"].isEnabled })
        pause(1)
        attachScreenshot("fr 2 source")
        app.buttons["onboarding.continue"].click()
        pause(1.5)
        attachScreenshot("fr 3 choice")
        app.buttons["onboarding.continue"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Tout est là." })
        pause(1)
        attachScreenshot("fr 4 import")
        for name in ["fr 5 getting around", "fr 6 default browser"] {
            app.buttons["onboarding.continue"].firstMatch.click()
            pause(1.5)
            attachScreenshot(name)
            if name == "fr 6 default browser" { app.buttons["onboarding.notNow"].click() }
        }
        pause(1.5)
        attachScreenshot("fr 7 ready")
    }
}

extension OnboardingE2ETests {
    /// Dark appearance: every step reads on the dark paper.
    func testDarkAppearance() {
        app.terminate()
        app.launchArguments += ["-browser.appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.start"].waitForExistence(timeout: TestApplication.launchTimeout))
        pause(2.5)
        attachScreenshot("dark 1 welcome")
        app.buttons["onboarding.start"].click()
        app.buttons["onboarding.source.Arc"].click()
        next("dark 2 source")
        pause(1.5)
        next("dark 3 choice")
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.app.descendants(matching: .any)["onboarding.title"].label == "Everything is here." })
        pause(1.5)
        next("dark 4 import")
        pause(1.5)
        next("dark 5 getting around")
        pause(1.5)
        attachScreenshot("dark 6 default browser")
    }
}

extension OnboardingE2ETests {
    private var title: String { app.descendants(matching: .any)["onboarding.title"].label }

    private func shortcut(_ label: String) -> XCUIElement {
        app.buttons.matching(identifier: "onboarding.shortcut").matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// The onboarding runs from the keyboard: Return continues, the arrows choose a browser, the Back command goes
    /// back, and Control-Tab or Command-K are tried in place without acting on the browser behind.
    func testKeyboardDrivesTheOnboarding() {
        app.typeKey(.return, modifierFlags: [])
        let chrome = app.buttons["onboarding.source.Google Chrome"], arc = app.buttons["onboarding.source.Arc"]
        XCTAssertTrue(chrome.waitForExistence(timeout: Self.renderTimeout), "Return starts")
        XCTAssertTrue(poll { chrome.isSelected })
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll { arc.isSelected && !chrome.isSelected }, "Down chooses the next browser")
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.continueButton.isEnabled })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { self.title == "Choose what to bring." }, "Return continues")
        // The Back command, as its shortcut or menu item: the test Mac's layout may not type Command-Left Bracket.
        app.menuBars.menuBarItems["History"].click()
        app.menuItems["Back"].click()
        XCTAssertTrue(poll { arc.exists && arc.isSelected }, "Back goes to the previous step, keeping the choice")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { self.title == "Choose what to bring." })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.title == "Everything is here." })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { self.title == "Within reach." })

        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(poll { self.shortcut("last tab").isSelected }, "Control-Tab is tried in place")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(poll { self.shortcut("control bar").isSelected }, "Command-K is tried in place")
        attachScreenshot("keyboard getting around")
        app.typeKey(.return, modifierFlags: [])
        // Never change the Mac's default browser from a test: Return here would ask macOS.
        XCTAssertTrue(app.buttons["onboarding.makeDefault"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["onboarding.notNow"].click()
        XCTAssertTrue(poll { self.title == "Fair winds." })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.app.groups["onboarding"].exists }, "Return starts browsing")
        XCTAssertTrue(labels(of: "sidebar.tab").isEmpty, "Control-Tab switched nothing behind the onboarding")
    }
}
