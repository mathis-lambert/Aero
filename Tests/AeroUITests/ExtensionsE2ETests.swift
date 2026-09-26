import AppKit
import XCTest

/// Installing and running an extension, and keeping it to its profile. See docs/EXTENSIONS.md.
@MainActor
final class ExtensionsE2ETests: BrowserE2ETestCase {
    private static let fixture = fixtures.appendingPathComponent("extension", isDirectory: true)

    func testFolderExtensionRunsInItsProfileOnly() {
        openSettings("Extensions")
        XCTAssertTrue(app.staticTexts["extensions.empty"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["extensions.addFromFolder"].click()
        let panel = app.sheets["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: Self.renderTimeout))
        // Pasted whole: the panel's Go to Folder field completes each typed character.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.fixture.path, forType: .string)
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(panel.textFields.firstMatch.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        let openButton = panel.buttons["Open"]
        XCTAssertTrue(poll { openButton.isEnabled }, "The panel reached the extension's folder")
        openButton.click()
        let accept = app.buttons["extensionRequest.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: Self.pageTimeout), "Installing shows what the extension asks for")
        attachScreenshot("extension-review", of: app.windows.firstMatch)
        accept.click()
        XCTAssertTrue(app.groups["extensions.row"].waitForExistence(timeout: Self.pageTimeout))
        app.buttons["extensions.pin"].click()
        closeSettings()

        open("site.html", expecting: "No cookie")
        XCTAssertTrue(page("Extension ran").waitForExistence(timeout: Self.pageTimeout), "The content script runs on matching pages")
        let button = app.buttons.matching(identifier: "extension.button").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.renderTimeout), "A pinned extension shows in the address bar")
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { button.value as? String == "ok" }, "Its worker ran past the API WebKit lacks, and its native host answered")
        button.click()
        XCTAssertTrue(app.webViews.staticTexts["Popup fixture"].waitForExistence(timeout: Self.pageTimeout), "Its popup opens from its button")
        attachScreenshot("extension-popup")
        app.typeKey(.escape, modifierFlags: [])

        quitAndRelaunch()
        tabRows.firstMatch.click()
        XCTAssertTrue(page("Extension ran").waitForExistence(timeout: Self.pageTimeout), "The extension is back after a relaunch")

        app.buttons["sidebar.addProfile"].click()
        app.textFields["profiles.name"].click()
        app.typeText("Work")
        app.buttons["profiles.save"].click()
        open("site.html", expecting: "No cookie")
        XCTAssertFalse(page("Extension ran").waitForExistence(timeout: 2), "Another profile does not run it")
        XCTAssertFalse(app.buttons.matching(identifier: "extension.button").firstMatch.exists)
    }
}
