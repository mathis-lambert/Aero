import XCTest

/// The app icon choice in Settings › Appearance. See docs/DESIGN.md › Choosing an icon.
@MainActor
final class AppIconE2ETests: BrowserE2ETestCase {
    private static let variant = "settings.appIcon.a-sun"
    private static let automatic = "settings.appIcon.automatic"

    func testAppIconChoicePersistsAcrossLaunches() {
        openAppearance()
        XCTAssertTrue(app.buttons[Self.automatic].isSelected, "Automatic is the default")
        app.buttons[Self.variant].click()
        XCTAssertTrue(app.buttons[Self.variant].isSelected)
        XCTAssertFalse(app.buttons[Self.automatic].isSelected)
        attachScreenshot("app-icon-chosen", of: app.windows["aero.settings"])

        relaunch()
        openAppearance()
        XCTAssertTrue(app.buttons[Self.variant].isSelected, "The choice survives a relaunch")

        app.buttons[Self.automatic].click()
        XCTAssertTrue(app.buttons[Self.automatic].isSelected)
        XCTAssertFalse(app.buttons[Self.variant].isSelected)
    }

    private func openAppearance() {
        app.typeKey(",", modifierFlags: .command)
        let section = app.buttons["settings.appearance"]
        XCTAssertTrue(section.waitForExistence(timeout: Self.renderTimeout))
        section.click()
        XCTAssertTrue(app.buttons[Self.automatic].waitForExistence(timeout: Self.renderTimeout))
    }
}
