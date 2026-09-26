import XCTest

/// The theme and app icon choices in Settings › General. See docs/DESIGN.md › App icon.
@MainActor
final class AppearanceE2ETests: BrowserE2ETestCase {
    private static let variant = "settings.appIcon.a-sun"
    private static let automatic = "settings.appIcon.automatic"
    private static let dark = "settings.theme.dark"
    private static let system = "settings.theme.system"
    /// The Finder's custom icon inside the app bundle, which the Finder, the Dock and Launchpad show.
    private static let customIcon = "Icon\r"

    /// The app under test sits next to the test runner in the build products.
    private var customIconFile: URL {
        Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Aero.app").appending(path: Self.customIcon)
    }

    func testAppearanceChoicesPersistAcrossLaunches() {
        openGeneral()
        XCTAssertTrue(app.buttons[Self.system].isSelected, "The theme follows the system by default")
        XCTAssertTrue(app.buttons[Self.automatic].isSelected, "Automatic is the default")
        app.buttons[Self.dark].click()
        app.buttons[Self.variant].click()
        XCTAssertTrue(app.buttons[Self.dark].isSelected)
        XCTAssertTrue(app.buttons[Self.variant].isSelected)
        XCTAssertFalse(app.buttons[Self.automatic].isSelected)
        XCTAssertTrue(poll { FileManager.default.fileExists(atPath: self.customIconFile.path) },
                      "The icon is set on the app itself, so it shows while Aero is closed")
        attachScreenshot("appearance-chosen", of: app)

        relaunch()
        openGeneral()
        XCTAssertTrue(app.buttons[Self.dark].isSelected, "The theme survives a relaunch")
        XCTAssertTrue(app.buttons[Self.variant].isSelected, "The icon survives a relaunch")

        app.buttons[Self.automatic].click()
        XCTAssertTrue(app.buttons[Self.automatic].isSelected)
        XCTAssertFalse(app.buttons[Self.variant].isSelected)
        XCTAssertTrue(poll { !FileManager.default.fileExists(atPath: self.customIconFile.path) },
                      "Automatic restores the system icon everywhere")
    }

    private func openGeneral() {
        app.typeKey(",", modifierFlags: .command)
        let section = app.buttons["settings.general"]
        XCTAssertTrue(section.waitForExistence(timeout: Self.renderTimeout))
        section.click()
        XCTAssertTrue(app.buttons[Self.automatic].waitForExistence(timeout: Self.renderTimeout))
    }
}
