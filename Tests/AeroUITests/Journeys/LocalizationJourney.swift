import XCTest

/// French with every string doubled and a right-to-left layout, across the screens with the most text, captured
/// for review. Missing translations are caught by StringCatalogTests. See AGENTS.md › Internationalization.
@MainActor
final class LocalizationJourney: E2ETestCase {
    private static let longName = "Documents de travail et références pour le projet"

    func testFrenchExpandedRightToLeftFits() throws {
        try launch(Launch(french: true, expandedStrings: true, rightToLeft: true)) { seed in
            seed.addTab("solid.html", title: "Solid fixture", place: .grid)
            seed.addTab("keys.html", title: Self.longName, place: .list(group: nil))
        }
        XCTAssertTrue(app.buttons["sidebar.newTab"].label.contains("Nouvel onglet"))
        XCTAssertTrue((controlBarInput.placeholderValue ?? "").contains("Rechercher ou saisir une adresse"))
        favoriteRows[Self.longName].hover()
        XCTAssertTrue(app.buttons["sidebar.removeFavorite"].isHittable, "A long name leaves room for its action")
        attachScreenshot("sidebar")

        app.buttons["sidebar.addSpace"].click()
        let name = app.textFields["spaces.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.renderTimeout))
        name.click()
        name.typeText("Recherche et documentation")
        XCTAssertTrue(app.buttons["spaces.newProfile"].isHittable && app.buttons["spaces.save"].isHittable)
        attachScreenshot("space editor")
        app.buttons["spaces.save"].click()
        XCTAssertTrue(poll { self.space("Recherche et documentation").isSelected })

        open("login.html", expecting: "Sign in")
        app.webViews.textFields["Username"].click()
        app.typeText("alice")
        app.webViews.secureTextFields["Password"].click()
        app.typeText("secret")
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(element("passwords.offer").waitForExistence(timeout: Self.renderTimeout))
        for button in ["passwords.never", "passwords.notNow", "passwords.save"] { XCTAssertTrue(app.buttons[button].isHittable, "\(button) fits") }
        attachScreenshot("save offer")
        app.buttons["passwords.notNow"].click()

        openSettings("General")
        attachScreenshot("settings general", of: app)
        selectSettingsSection("updates")
        XCTAssertTrue(app.staticTexts["updates.disabled"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(app.buttons["updates.check"].isHittable, "The update action fits expanded French in RTL")
        attachScreenshot("software updates expanded French RTL", of: app)
        selectSettingsSection("profiles")
        app.buttons["profiles.row.Personal"].click()
        replaceText(of: app.textFields["profiles.name"], with: "Profil personnel et documentation\n")
        attachScreenshot("profile detail", of: app)
        selectSettingsSection("spaces")
        attachScreenshot("spaces", of: app)
        selectSettingsSection("passwords")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "passwords.profile.")).firstMatch.click()
        app.buttons["passwords.import"].click()
        XCTAssertTrue(app.buttons["passwords.importCSV"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("password import", of: app)
        selectSettingsSection("Shortcuts")
        replaceText(of: app.searchFields.firstMatch, with: "zoom")
        XCTAssertTrue(element("shortcuts.command.zoomIn").exists && element("shortcuts.command.resetZoom").exists, "Commands are found by their French titles")
        attachScreenshot("shortcuts", of: app)
        element("shortcuts.settings").click()
        attachScreen("shortcut options")
        app.typeKey(.escape, modifierFlags: [])
    }
}
