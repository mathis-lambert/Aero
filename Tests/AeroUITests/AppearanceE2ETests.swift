import XCTest

/// The theme and app icon choices in Settings › General. See docs/DESIGN.md › App icon.
@MainActor
final class AppearanceE2ETests: BrowserE2ETestCase {
    private static let variant = "settings.appIcon.a-sun"
    private static let automatic = "settings.appIcon.automatic"
    private static let dark = "Dark"
    private static let system = "System"
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
        XCTAssertTrue(isChosen(Self.system), "The theme follows the system by default")
        XCTAssertTrue(app.buttons[Self.automatic].isSelected, "Automatic is the default")
        theme(Self.dark).click()
        app.buttons[Self.variant].click()
        XCTAssertTrue(isChosen(Self.dark))
        XCTAssertTrue(app.buttons[Self.variant].isSelected)
        XCTAssertFalse(app.buttons[Self.automatic].isSelected)
        XCTAssertTrue(poll { FileManager.default.fileExists(atPath: self.customIconFile.path) },
                      "The icon is set on the app itself, so it shows while Aero is closed")
        attachScreenshot("appearance-chosen", of: app)

        relaunch()
        openGeneral()
        XCTAssertTrue(isChosen(Self.dark), "The theme survives a relaunch")
        XCTAssertTrue(app.buttons[Self.variant].isSelected, "The icon survives a relaunch")

        app.buttons[Self.automatic].click()
        XCTAssertTrue(app.buttons[Self.automatic].isSelected)
        XCTAssertFalse(app.buttons[Self.variant].isSelected)
        XCTAssertTrue(poll { !FileManager.default.fileExists(atPath: self.customIconFile.path) },
                      "Automatic restores the system icon everywhere")
    }

    private func openGeneral() {
        openSettings("General")
        XCTAssertTrue(app.buttons[Self.automatic].waitForExistence(timeout: Self.renderTimeout))
    }

    private func theme(_ name: String) -> XCUIElement { app.radioButtons[name] }

    private func isChosen(_ name: String) -> Bool { theme(name).value as? Int == 1 }
}
