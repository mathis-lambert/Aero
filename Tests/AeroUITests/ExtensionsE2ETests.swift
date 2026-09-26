import AppKit
import XCTest

/// Installing and running an extension, and keeping it to its profile. See docs/EXTENSIONS.md.
@MainActor
final class ExtensionsE2ETests: BrowserE2ETestCase {
    /// Read by the app from the repository: the sandboxed test runner has no folder the app may read.
    private static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/extension", isDirectory: true)

    func testFolderExtensionRunsInItsProfileOnly() {
        openSettings("Extensions")
        XCTAssertTrue(app.staticTexts["extensions.empty"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["extensions.addFromFolder"].click()
        // Pasted whole: the panel's Go to Folder field completes each typed character.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.fixture.path, forType: .string)
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
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
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { button.value as? String == "ok" }, "Its worker ran, past the API WebKit lacks")
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

    private func page(_ text: String) -> XCUIElement { app.webViews.staticTexts[text] }
}
