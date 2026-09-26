import AppKit
import XCTest

/// Creating, editing and switching profiles from the sidebar. See docs/PROFILES.md.
@MainActor
final class ProfilesE2ETests: BrowserE2ETestCase {
    func testProfilesSwitchFromTheFooter() {
        XCTAssertEqual(labels(of: "sidebar.profile"), ["Personal"], "One profile shows one icon")
        open("solid.html", expecting: "Solid fixture")

        app.buttons["sidebar.addProfile"].click()
        let name = app.textFields["profiles.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.renderTimeout))
        name.click()
        name.typeText("Work")
        paste("🚀", into: app.textFields["profiles.emoji"])
        app.buttons["profiles.save"].click()
        XCTAssertEqual(labels(of: "sidebar.profile"), ["Personal", "Work"])
        XCTAssertTrue(poll { self.isSelected("Work") }, "A new profile is selected")
        open("keys.html", expecting: "No shortcut yet")
        attachScreenshot("profiles-footer")

        profile("Personal").click()
        XCTAssertTrue(poll { self.isSelected("Personal") })
        XCTAssertTrue(app.webViews.staticTexts["Solid fixture"].waitForExistence(timeout: Self.pageTimeout),
                      "Switching back shows the profile's last tab")

        profile("Work").click()
        XCTAssertTrue(poll { self.isSelected("Work") })
        XCTAssertTrue(app.webViews.staticTexts["No shortcut yet"].waitForExistence(timeout: Self.pageTimeout))

        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.profile"), ["Personal", "Work"])
        editProfile("Work")
        XCTAssertEqual(app.textFields["profiles.emoji"].value as? String, "🚀", "The emoji survives a relaunch")
    }

    func testCreateRenameAndRestoreProfile() {
        app.buttons["sidebar.addProfile"].click()
        app.textFields["profiles.name"].click()
        app.typeText("Work")
        app.buttons["profiles.save"].click()
        XCTAssertTrue(poll { self.isSelected("Work") })

        editProfile("Work")
        app.textFields["profiles.name"].click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Studio")
        app.buttons["profiles.save"].click()
        quitAndRelaunch()
        XCTAssertEqual(labels(of: "sidebar.profile"), ["Personal", "Studio"])
    }

    func testProfileFormRejectsEmptyName() {
        app.buttons["sidebar.addProfile"].click()
        XCTAssertTrue(app.buttons["profiles.save"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["profiles.save"].isEnabled)
        paste("abc", into: app.textFields["profiles.emoji"])
        XCTAssertEqual(app.textFields["profiles.emoji"].value as? String ?? "", "", "Only an emoji is kept")
    }

    private func profile(_ name: String) -> XCUIElement {
        app.buttons.matching(identifier: "sidebar.profile").matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    private func editProfile(_ name: String) {
        profile(name).rightClick()
        app.menuItems["Edit profile…"].click()
        XCTAssertTrue(app.textFields["profiles.name"].waitForExistence(timeout: Self.renderTimeout))
    }

    /// Typing cannot produce emoji in UI tests, so text goes through the pasteboard, like a pick
    /// from the Character Viewer.
    private func paste(_ text: String, into field: XCUIElement) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        field.click()
        app.typeKey("v", modifierFlags: .command)
    }

    /// Quits from the prompt, so the session is saved, then launches again.
    private func quitAndRelaunch() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.groups["quit.prompt"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout))
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    private func isSelected(_ name: String) -> Bool { profile(name).isSelected }
}
