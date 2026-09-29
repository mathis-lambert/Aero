import AppKit
import XCTest

/// The site in the selected tab and what runs on it: controls, data and permissions, ad blocking, picture in picture
/// and extensions. List conversion and extension packages are covered by FilterListConverterTests and
/// ExtensionPackageTests. See docs/SITE_CONTROLS.md and docs/EXTENSIONS.md.
@MainActor
final class SiteJourneys: E2ETestCase {
    /// The control center describes the site; clearing cookies or all data reloads the page without them and
    /// leaves other sites alone; a permission decision survives a relaunch.
    func testSiteControlsDataAndPermissions() throws {
        try launch()
        XCTAssertFalse(app.buttons["address.controlCenter"].exists, "The New Tab page has no site controls")
        open("site.html", host: "127.0.0.1", expecting: "No cookie")
        setCookie()
        open("site.html", expecting: "No cookie")
        setCookie()

        app.buttons["address.controlCenter"].click()
        let security = element("controlCenter.security")
        XCTAssertTrue(security.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(security.label, "Not secure", "A plain HTTP page is not secure")
        XCTAssertTrue(app.buttons["controlCenter.share"].exists && app.buttons["controlCenter.ads"].exists)
        attachScreenshot("control center")
        app.menuButtons["controlCenter.more"].click()
        XCTAssertTrue(app.menuItems["Clear Cache"].exists && app.menuItems["Clear Cookies"].exists)
        app.windows.menuItems["Site Settings…"].click()
        XCTAssertTrue(app.popUpButtons["siteSettings.camera"].waitForExistence(timeout: Self.renderTimeout), "Site settings open inside the control center")
        app.typeKey(.escape, modifierFlags: [])

        reloadButtonMenu("Clear Cookies")
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "Clearing cookies reloads the page without them")
        setCookie()
        reloadButtonMenu("Site Settings…")
        let cookies = app.staticTexts["siteSettings.cookies"]
        XCTAssertTrue(poll { cookies.value as? String == "1 cookie" }, "Site settings count the site's cookies")
        attachScreenshot("site settings")
        app.buttons["siteSettings.deleteData"].click()
        XCTAssertTrue(poll { cookies.value as? String == "No cookies" })
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "Deleting data reloads the page")
        // Using the devices would show macOS's own prompt first, whatever the site's decision.
        app.popUpButtons["siteSettings.camera"].click()
        app.menuItems["Block"].click()
        XCTAssertTrue(poll { self.app.popUpButtons["siteSettings.camera"].value as? String == "Block" })
        app.typeKey(.escape, modifierFlags: [])
        tabRows.element(boundBy: 0).click()
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.pageTimeout), "Another site keeps its cookies")

        quitAndRelaunch()
        tabRows.element(boundBy: 1).click()
        reloadButtonMenu("Site Settings…")
        XCTAssertTrue(app.popUpButtons["siteSettings.camera"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(app.popUpButtons["siteSettings.camera"].value as? String, "Block", "Decisions survive a relaunch")
        XCTAssertEqual(app.popUpButtons["siteSettings.microphone"].value as? String, "Ask")
    }

    /// The fixture list blocks third-party trackers and hides banners until the site is allowed; a playing video
    /// moves to picture in picture when its tab is left, unless the site is turned off.
    func testAdsBlockingAndPictureInPicture() throws {
        try launch()
        open("ads.html", expecting: "Ads fixture")
        // The list compiles right after launch; a page opened before gets it on its next load.
        XCTAssertTrue(poll(timeout: Self.pageTimeout) {
            if self.page("Tracker blocked").exists { return true }
            self.app.typeKey("r", modifierFlags: .command)
            return self.page("Tracker blocked").waitForExistence(timeout: 1)
        }, "A third-party request matching the list is blocked")
        XCTAssertTrue(page("First party loaded").exists, "The site's own requests are kept")
        XCTAssertTrue(page("Banner hidden").exists, "Element hiding applies")
        XCTAssertFalse(server.requests(for: "filters.txt").isEmpty, "The list came from the fixture server, never the internet")
        app.buttons["address.controlCenter"].click()
        let ads = app.buttons["controlCenter.ads"]
        XCTAssertTrue(ads.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(ads.value as? String, "On")
        ads.click()
        XCTAssertTrue(page("Tracker loaded").waitForExistence(timeout: Self.pageTimeout), "Allowing the site reloads it unblocked")
        XCTAssertTrue(page("Banner shown").exists)
        app.typeKey(.escape, modifierFlags: [])

        open("video.html", expecting: "Modes inline")
        app.webViews.buttons["Play"].click()
        app.typeKey("t", modifierFlags: .command)
        pause(2) // Picture in picture starts once the tab has been hidden a moment.
        // The picture in picture window may cover the sidebar, so the tab comes back from the keyboard.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(page("Modes inline picture-in-picture inline").waitForExistence(timeout: Self.pageTimeout),
                      "The video went to picture in picture and came back with its tab")
        app.buttons["address.controlCenter"].click()
        let pictureInPicture = app.buttons["controlCenter.pictureInPicture"]
        XCTAssertTrue(pictureInPicture.waitForExistence(timeout: Self.renderTimeout))
        pictureInPicture.click()
        XCTAssertTrue(poll { pictureInPicture.value as? String == "Off" })
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("t", modifierFlags: .command)
        pause(2)
        app.typeKey("2", modifierFlags: .command)
        pause(1)
        XCTAssertTrue(page("Modes inline picture-in-picture inline").exists, "A site turned off stays inline")
    }

    /// Installing asks for what the extension wants; its content script, button, popup, worker and native host run
    /// in its profile only; a rejected update keeps the running version; removal lasts across relaunches.
    func testAnExtensionRunsInItsProfileOnly() throws {
        try launch()
        openSettings("Extensions")
        XCTAssertTrue(app.staticTexts["extensions.empty"].waitForExistence(timeout: Self.renderTimeout))
        chooseFolder("basic")
        let accept = app.buttons["extensionRequest.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: Self.pageTimeout), "Installing shows what the extension asks for")
        attachScreenshot("extension review")
        accept.click()
        XCTAssertTrue(app.groups["extensions.row"].waitForExistence(timeout: Self.pageTimeout))
        app.buttons["extensions.pin"].click()
        chooseFolder("update")
        XCTAssertTrue(app.buttons["extensionRequest.cancel"].waitForExistence(timeout: Self.pageTimeout), "An update asks again")
        app.buttons["extensionRequest.cancel"].click()
        closeSettings()

        open("site.html", expecting: "No cookie")
        XCTAssertTrue(page("Extension ran").waitForExistence(timeout: Self.pageTimeout), "The content script runs on matching pages")
        XCTAssertFalse(page("Rejected extension ran").exists, "The rejected update never runs")
        let button = app.buttons.matching(identifier: "extension.button").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.renderTimeout), "A pinned extension shows by the address")
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { button.value as? String == "ok" }, "Its worker ran past the API WebKit lacks, and its native host answered")
        button.rightClick()
        for item in ["Unpin Extension", "Manage Extensions…", "Remove Extension"] {
            XCTAssertTrue(app.windows.menuItems[item].exists, "Its context menu shows \(item)")
        }
        app.typeKey(.escape, modifierFlags: [])
        button.click()
        XCTAssertTrue(page("Popup fixture").waitForExistence(timeout: Self.pageTimeout), "Its popup opens from its button")
        attachScreenshot("extension popup")
        app.typeKey(.escape, modifierFlags: [])

        quitAndRelaunch()
        tabRows.firstMatch.click()
        XCTAssertTrue(page("Extension ran").waitForExistence(timeout: Self.pageTimeout), "The extension is back after a relaunch")
        createSpace("Work", newProfile: "Work")
        open("site.html", expecting: "No cookie")
        XCTAssertFalse(page("Extension ran").waitForExistence(timeout: 2), "Another profile does not run it")
        XCTAssertFalse(button.exists)

        space("Main").click()
        openSettings("Extensions")
        app.buttons["extensions.remove"].click()
        XCTAssertTrue(app.staticTexts["extensions.empty"].waitForExistence(timeout: Self.pageTimeout))
        closeSettings()
        quitAndRelaunch()
        space("Main").click()
        tabRows.firstMatch.click()
        XCTAssertFalse(page("Extension ran").waitForExistence(timeout: 2), "Removal survives a relaunch")
    }

    // MARK: - Helpers

    private func setCookie() {
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.renderTimeout))
    }

    private func reloadButtonMenu(_ item: String) {
        app.buttons["sidebar.reload"].rightClick()
        app.windows.menus["sidebar.reload"].menuItems[item].click()
    }

    /// Chooses an extension folder of `Fixtures/extensions` in the open panel.
    private func chooseFolder(_ name: String) {
        XCTAssertTrue(poll { self.app.buttons["extensions.addFromFolder"].isEnabled })
        app.buttons["extensions.addFromFolder"].click()
        let panel = app.sheets["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: Self.renderTimeout))
        // Pasted whole: the panel's Go to Folder field completes each typed character.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.fixtures.appendingPathComponent("extensions/\(name)").path, forType: .string)
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(panel.textFields.firstMatch.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey("v", modifierFlags: .command)
        app.typeKey(.return, modifierFlags: [])
        let openButton = panel.buttons["Open"]
        XCTAssertTrue(poll { openButton.isEnabled }, "The panel reached the extension's folder")
        openButton.click()
    }
}
