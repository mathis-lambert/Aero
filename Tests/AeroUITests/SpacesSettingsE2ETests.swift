import XCTest

@MainActor
final class SpacesSettingsE2ETests: BrowserE2ETestCase {
    func testHierarchyAutomaticNamesAndSpaceOrderingPersist() {
        createSpace("Reading")
        openSettings("profiles")
        XCTAssertFalse(app.textFields["profiles.name"].exists)
        app.buttons["profiles.row.Personal"].click()
        XCTAssertTrue(app.textFields["profiles.name"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["profiles.save"].exists)
        let profileName = app.textFields["profiles.name"]
        profileName.click()
        profileName.typeKey("a", modifierFlags: .command)
        profileName.typeText("Personal identity")
        // Leaving the detail page commits without an explicit Save or Return.
        app.buttons["settings.back"].click()
        XCTAssertTrue(app.buttons["profiles.row.Personal identity"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("profiles-list")
        app.buttons["profiles.row.Personal identity"].click()
        attachScreenshot("profile-detail")
        app.buttons["Manage spaces…"].click()
        XCTAssertTrue(app.buttons["spaces.row.Reading"].waitForExistence(timeout: Self.renderTimeout))
        dragSpace("Reading", above: "Main")
        app.buttons["spaces.row.Reading"].click()
        let name = app.textFields["spaces.name"]
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Research")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(app.buttons["spaces.save"].exists)
        let emoji = app.textFields["spaces.emoji"]
        emoji.click()
        emoji.typeText("🚀")
        app.typeKey(.tab, modifierFlags: [])
        attachScreenshot("space-detail")
        app.buttons["settings.back"].click()
        attachScreenshot("spaces-list")
        closeSettings()
        let main = space("Main"), research = space("Research")
        XCTAssertTrue(research.waitForExistence(timeout: Self.renderTimeout))
        let midpoint = (main.frame.midX + research.frame.midX) / 2
        let sidebar = app.buttons["sidebar.newTab"].firstMatch.frame
        XCTAssertEqual(midpoint, sidebar.midX, accuracy: 3, "Space icons are centered in the sidebar")
        attachScreenshot("centered-space-icons")
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Research", "Main"])
        openSettings("profiles")
        XCTAssertTrue(app.buttons["profiles.row.Personal identity"].exists)
        selectSettingsSection("spaces")
        app.buttons["spaces.row.Research"].click()
        XCTAssertEqual(app.textFields["spaces.emoji"].value as? String, "🚀")
    }

    func testCustomColorFromSystemPopoverPersists() {
        openSettings("spaces")
        app.buttons["spaces.row.Main"].click()
        let well = app.colorWells["spaces.customColor"]
        XCTAssertTrue(well.waitForExistence(timeout: Self.renderTimeout))
        let initial = well.value as? String
        well.click()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: Self.renderTimeout), "The color well opens the system popover, not the panel")
        XCTAssertFalse(app.windows["Colors"].exists)
        attachScreenshot("custom-color-popover")
        // A swatch of the popover's grid, away from its edges and its Show Colors button.
        popover.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).click()
        XCTAssertTrue(poll { (well.value as? String) != initial })
        let chosen = well.value as? String
        app.typeKey(.escape, modifierFlags: [])
        attachScreenshot("custom-color-selected")
        closeSettings()
        quitAndRelaunch()
        openSettings("spaces")
        app.buttons["spaces.row.Main"].click()
        XCTAssertTrue(app.colorWells["spaces.customColor"].waitForExistence(timeout: Self.renderTimeout))
        // Stored as #RRGGBB: each component comes back to within half an 8-bit step.
        let restored = components(app.colorWells["spaces.customColor"].value), picked = components(chosen)
        XCTAssertEqual(restored.count, 3)
        for (value, expected) in zip(restored, picked) { XCTAssertEqual(value, expected, accuracy: 0.5 / 255 + 0.0001) }
    }

    /// A color well's value reads "rgb R G B A".
    private func components(_ value: Any?) -> [Double] {
        ((value as? String) ?? "").split(separator: " ").dropFirst().prefix(3).compactMap { Double($0) }
    }

    func testDragSpaceOrderingPersists() {
        createSpace("Reading")
        createSpace("Work")
        openSettings("spaces")
        dragSpace("Work", above: "Main")
        attachScreenshot("spaces-after-drag-up")
        XCTAssertTrue(poll { self.app.buttons["spaces.row.Work"].frame.minY < self.app.buttons["spaces.row.Main"].frame.minY })
        let source = app.images["spaces.drag.Work"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.images["spaces.drag.Reading"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 7))
        source.click(forDuration: 0.5, thenDragTo: end)
        XCTAssertTrue(poll { self.app.buttons["spaces.row.Work"].frame.minY > self.app.buttons["spaces.row.Reading"].frame.minY })
        attachScreenshot("spaces-drag-order")
        closeSettings()
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main", "Reading", "Work"])
    }

    private func dragSpace(_ name: String, above destination: String) {
        let row = app.buttons["spaces.row.\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout))
        let source = app.images["spaces.drag.\(name)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = app.images["spaces.drag.\(destination)"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -7))
        source.click(forDuration: 0.5, thenDragTo: target)
    }

    func testSettingsHierarchyInFrenchAndRightToLeftLayout() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
            + ["-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"]
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        openSettings("profiles")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "profiles.row.")).firstMatch.click()
        let name = app.textFields["profiles.name"]
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Profil personnel et documentation")
        app.typeKey(.return, modifierFlags: [])
        attachScreenshot("profile-detail-french-rtl")
        selectSettingsSection("spaces")
        attachScreenshot("spaces-list-french-rtl")
    }
}
