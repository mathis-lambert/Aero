import AppKit
import XCTest

/// The site in the selected tab: address actions, control center, site data and permissions, ad
/// blocking and automatic picture in picture. See docs/SITE_CONTROLS.md.
@MainActor
final class SiteControlsE2ETests: BrowserE2ETestCase {
    func testAddressActionsAndControlCenter() {
        open("site.html", expecting: "No cookie")
        NSPasteboard.general.clearContents()
        app.buttons["address.copyLink"].click()
        XCTAssertTrue(poll { NSPasteboard.general.string(forType: .string) == self.server.url("site.html").absoluteString },
                      "Copy link puts the page's address on the pasteboard")

        app.buttons["address.controlCenter"].click()
        let security = app.descendants(matching: .any).matching(identifier: "controlCenter.security").firstMatch
        XCTAssertTrue(security.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(security.label, "Not secure", "A plain HTTP page is not secure")
        XCTAssertTrue(app.buttons["controlCenter.share"].exists)
        XCTAssertTrue(app.buttons["controlCenter.ads"].exists)
        attachScreenshot("control-center")
        app.menuButtons["controlCenter.more"].click()
        XCTAssertTrue(app.menuItems["Clear cache"].exists && app.menuItems["Clear cookies"].exists)
        app.menuItems["Site settings…"].click()
        XCTAssertTrue(app.popUpButtons["siteSettings.camera"].waitForExistence(timeout: Self.renderTimeout),
                      "Site settings opens inside the control center")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.buttons["address.copyLink"].exists, "The New Tab page has no address actions")
        XCTAssertFalse(app.buttons["address.controlCenter"].exists)
    }

    func testAdsAndTrackersAreBlockedUnlessAllowed() {
        open("ads.html", expecting: "Ads fixture")
        // The test list compiles right after launch; pages opened before get it on their next load.
        XCTAssertTrue(poll(timeout: Self.pageTimeout) {
            if self.page("Tracker blocked").exists { return true }
            self.app.typeKey("r", modifierFlags: .command)
            return self.page("Tracker blocked").waitForExistence(timeout: 1)
        }, "A third-party request matching the list is blocked")
        XCTAssertTrue(page("First party loaded").waitForExistence(timeout: Self.renderTimeout), "The site's own requests are kept")
        XCTAssertTrue(page("Banner hidden").waitForExistence(timeout: Self.renderTimeout), "Element hiding applies")
        XCTAssertFalse(server.requests(for: "filters.txt").isEmpty, "The list came from the fixture server")

        app.buttons["address.controlCenter"].click()
        let ads = app.buttons["controlCenter.ads"]
        XCTAssertTrue(ads.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(ads.value as? String, "On")
        ads.click()
        XCTAssertTrue(poll { ads.value as? String == "Off" })
        XCTAssertTrue(page("Tracker loaded").waitForExistence(timeout: Self.pageTimeout), "Allowing the site reloads it unblocked")
        XCTAssertTrue(page("Banner shown").waitForExistence(timeout: Self.renderTimeout))
    }

    func testVideoMovesToPictureInPictureWhenLeavingTheTab() {
        open("video.html", expecting: "Modes inline")
        app.webViews.buttons["Play"].click()
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        pause(for: 2)
        // The picture in picture window may sit over the sidebar, so the tab comes back from the keyboard.
        app.typeKey(.tab, modifierFlags: .control)
        XCTAssertTrue(page("Modes inline picture-in-picture inline").waitForExistence(timeout: Self.pageTimeout),
                      "The playing video went to picture in picture and came back with its tab")

        app.buttons["address.controlCenter"].click()
        let pictureInPicture = app.buttons["controlCenter.pictureInPicture"]
        XCTAssertTrue(pictureInPicture.waitForExistence(timeout: Self.renderTimeout))
        pictureInPicture.click()
        XCTAssertTrue(poll { pictureInPicture.value as? String == "Off" })
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("t", modifierFlags: .command)
        pause(for: 2)
        app.typeKey(.tab, modifierFlags: .control)
        pause(for: 1)
        XCTAssertTrue(page("Modes inline picture-in-picture inline").exists, "A site turned off stays inline")
    }

    func testSiteDataClearsAndPermissionsPersist() {
        open("site.html", host: "127.0.0.1", expecting: "No cookie")
        setCookie()
        open("site.html", expecting: "No cookie")
        setCookie()

        siteMenu("Clear cookies")
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "Clearing cookies reloads the page without them")
        setCookie()
        siteMenu("Site settings…")
        let cookies = app.staticTexts["siteSettings.cookies"]
        XCTAssertTrue(cookies.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(poll { cookies.value as? String == "1 cookie" }, "The popover counts the site's cookies")
        attachScreenshot("site-settings")
        app.buttons["siteSettings.deleteData"].click()
        XCTAssertTrue(poll { cookies.value as? String == "No cookies" })
        XCTAssertTrue(page("No cookie").waitForExistence(timeout: Self.pageTimeout), "Deleting data reloads the page")

        // Using the devices would show macOS's own authorization prompt first, whatever the site's decision.
        choose("Block", for: "siteSettings.camera")
        app.typeKey(.escape, modifierFlags: [])

        tabRows.element(boundBy: 0).click()
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.pageTimeout), "Another site keeps its cookies")

        quitAndRelaunch()
        tabRows.element(boundBy: 1).click()
        siteMenu("Site settings…")
        XCTAssertTrue(app.popUpButtons["siteSettings.camera"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(app.popUpButtons["siteSettings.camera"].value as? String, "Block", "Decisions survive a relaunch")
        XCTAssertEqual(app.popUpButtons["siteSettings.microphone"].value as? String, "Ask")
    }

    private func page(_ text: String) -> XCUIElement { app.webViews.staticTexts[text] }

    private func setCookie() {
        app.webViews.buttons["Set cookie"].click()
        XCTAssertTrue(page("Cookie set").waitForExistence(timeout: Self.renderTimeout))
    }

    private func siteMenu(_ item: String) {
        app.buttons["sidebar.reload"].rightClick()
        app.menuItems[item].click()
    }

    private func choose(_ decision: String, for permission: String) {
        app.popUpButtons[permission].click()
        app.menuItems[decision].click()
        XCTAssertTrue(poll { self.app.popUpButtons[permission].value as? String == decision })
    }

    private func pause(for seconds: TimeInterval) { RunLoop.current.run(until: .now.addingTimeInterval(seconds)) }
}
