import XCTest

/// Saving, filling and managing passwords, per profile. See docs/PASSWORDS.md › Failure modes.
/// Items are created by the app under a test creator and namespace, never among real passwords.
@MainActor
final class PasswordsE2ETests: BrowserE2ETestCase {
    private var username: XCUIElement { app.webViews.textFields["Username"] }
    private var password: XCUIElement { app.webViews.secureTextFields["Password"] }
    private var offer: XCUIElement { app.descendants(matching: .any).matching(identifier: "passwords.offer").firstMatch }
    private var picker: XCUIElement { app.descendants(matching: .any).matching(identifier: "passwords.picker").firstMatch }

    // Failure modes 5, 8 and 10: save, fill into the focused form, update instead of duplicating.
    func testSavesFillsAndUpdatesPassword() {
        signIn(as: "alice", with: "hunter2")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout), "Submitting offers to save")
        attachScreenshot("save-offer")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { !self.offer.exists })

        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page("Filled nobody with 0 characters").waitForExistence(timeout: Self.pageTimeout))
        username.click()
        let login = app.buttons["passwords.login"].firstMatch
        XCTAssertTrue(login.waitForExistence(timeout: Self.renderTimeout), "The saved login is offered under the field")
        attachScreenshot("account-list")
        login.click()
        XCTAssertTrue(page("Filled alice with 7 characters").waitForExistence(timeout: Self.renderTimeout), "Choosing it fills the form")
        XCTAssertFalse(picker.exists, "The list closes after filling")

        // The same password only records its use.
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(page("Signed in as alice").waitForExistence(timeout: Self.renderTimeout))
        pause(1)
        XCTAssertFalse(offer.exists, "An unchanged password is not offered again")

        signIn(as: "alice", with: "hunter3", reloading: true)
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(app.buttons["passwords.save"].label, "Update", "A known username with a new password offers Update")
        XCTAssertFalse(app.buttons["passwords.never"].exists)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { !self.offer.exists })

        openPasswordProfile()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "passwords.row").firstMatch.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(labels(of: "passwords.row").count, 1, "Updating kept one login")
    }

    func testEscapeDismissesPasswordOfferWithoutSaving() {
        signIn(as: "cancelled", with: "secret")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll { !self.offer.exists })

        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page("Filled nobody with 0 characters").waitForExistence(timeout: Self.pageTimeout))
        username.click()
        XCTAssertFalse(app.buttons["passwords.login"].exists, "Escape did not save the password")
    }

    func testAccountListClosesWhenFieldLosesFocus() {
        signIn(as: "alice", with: "secret")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.save"].click()
        XCTAssertTrue(poll { !self.offer.exists })

        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page("Filled nobody with 0 characters").waitForExistence(timeout: Self.pageTimeout))
        username.click()
        XCTAssertTrue(picker.waitForExistence(timeout: Self.renderTimeout))
        app.webViews.staticTexts["Sign in"].firstMatch.click()
        XCTAssertTrue(poll { !self.picker.exists }, "The account list closes when the field loses focus")
    }

    func testSourceBuildDoesNotOfferUnavailablePasskeys() {
        open("passkeys.html", expecting: "Passkey availability")
        XCTAssertTrue(page("Passkeys unavailable").waitForExistence(timeout: Self.renderTimeout))
    }

    func testSaveOfferFitsFrenchLayout() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))

        signIn(as: "alice", with: "secret")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(app.buttons["passwords.never"].exists)
        XCTAssertTrue(app.buttons["passwords.notNow"].exists)
        XCTAssertTrue(app.buttons["passwords.save"].exists)
        attachScreenshot("save-offer-french")
    }

    // Failure mode 4: Never for this site is the site's decision and survives relaunch.
    func testNeverForThisSiteSurvivesRelaunch() {
        signIn(as: "bob", with: "secret")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.never"].click()
        XCTAssertTrue(poll { !self.offer.exists })
        quitAndRelaunch()
        signIn(as: "bob", with: "secret")
        XCTAssertTrue(page("Signed in as bob").waitForExistence(timeout: Self.renderTimeout))
        pause(1)
        XCTAssertFalse(offer.exists, "A blocked site is never offered to save")
        // Another site still is.
        signIn(as: "bob", with: "secret", host: "127.0.0.1")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
    }

    // Failure mode 9: the strong password fills every new-password field of the form.
    func testSuggestsStrongPasswordOnSignUp() {
        open("signup.html", expecting: "Create account")
        app.webViews.secureTextFields["New password"].click()
        let suggestion = app.buttons["passwords.suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: Self.renderTimeout), "A new-password field offers a strong password")
        suggestion.click()
        XCTAssertTrue(page("Passwords match with 20 characters").waitForExistence(timeout: Self.renderTimeout))
        app.webViews.buttons["Create account"].click()
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout), "The new account's password is offered to save")
    }

    // Failure mode 3: spaces of another profile never see the login; the profile's own spaces do.
    func testProfilesKeepTheirOwnPasswords() {
        signIn(as: "carol", with: "personal")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.save"].click()

        createSpace("Work", newProfile: "Work")
        open("login.html", expecting: "Sign in")
        username.click()
        pause(1)
        XCTAssertFalse(app.buttons["passwords.login"].exists, "Another profile is not offered the login")

        createSpace("Reading")
        open("login.html", expecting: "Sign in")
        username.click()
        pause(1)
        XCTAssertFalse(app.buttons["passwords.login"].exists, "A space created from Work uses the Work profile")

        space("Main").click()
        open("login.html", expecting: "Sign in")
        username.click()
        XCTAssertTrue(app.buttons["passwords.login"].firstMatch.waitForExistence(timeout: Self.renderTimeout), "The profile's own space is")
    }

    // Managing: the login is listed in Settings and deleted from there.
    func testSettingsListsAndDeletesPasswords() {
        signIn(as: "dave", with: "letmein")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.save"].click()
        XCTAssertTrue(poll { !self.offer.exists })

        openPasswordProfile()
        let row = app.descendants(matching: .any).matching(identifier: "passwords.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(row.label, "localhost, dave")
        let orange = ScreenshotColor(red: 255, green: 90, blue: 0)
        XCTAssertTrue(poll { orange.isShown(in: row, at: CGPoint(x: 26, y: row.frame.height / 2)) },
                      "The saved login reuses the site's favicon")
        attachScreenshot("settings")
        row.click()
        XCTAssertTrue(app.buttons["passwords.reveal"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.delete"].click()
        let confirm = app.windows.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.renderTimeout))
        confirm.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "passwords.empty").firstMatch.waitForExistence(timeout: Self.renderTimeout))
        closeSettings()

        open("login.html", expecting: "Sign in")
        username.click()
        pause(1)
        XCTAssertFalse(app.buttons["passwords.login"].exists, "A deleted login is not offered")
    }

    // Editing a saved password must dismiss the editor without invalidating its text bindings.
    func testSettingsEditsPasswordWithoutCrashing() {
        signIn(as: "erin", with: "before-edit")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.save"].click()
        XCTAssertTrue(poll { !self.offer.exists })

        openPasswordProfile()
        let row = app.descendants(matching: .any).matching(identifier: "passwords.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout))
        row.click()
        XCTAssertTrue(app.buttons["passwords.reveal"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords-login")
        app.buttons["passwords.reveal"].click()

        let editor = app.textFields["passwords.edit.password"]
        XCTAssertTrue(editor.waitForExistence(timeout: Self.renderTimeout))
        editor.click()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("after-edit")
        app.buttons["passwords.edit.save"].click()

        XCTAssertTrue(app.buttons["passwords.reveal"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(app.buttons["passwords.delete"].exists, "The app and saved login remain available after saving")
        app.buttons["passwords.reveal"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(editor.value as? String, "after-edit", "The edited password was saved to the test keychain")
    }

    // A username-only first page must carry its account to the password page in this tab.
    func testSavesUsernameFromTwoStepSignIn() {
        open("login-steps-username.html", expecting: "Enter your email")
        let email = app.webViews.textFields["Email address"]
        email.click()
        email.typeText("alice@example.test")
        app.webViews.buttons["Next"].click()
        XCTAssertTrue(page("Enter your password").waitForExistence(timeout: Self.pageTimeout))

        let secondStepPassword = app.webViews.secureTextFields["Password"]
        secondStepPassword.click()
        secondStepPassword.typeText("two-step-secret")
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertTrue(offer.staticTexts["alice@example.test"].exists, "The offer names the first step's account")
        app.buttons["passwords.save"].click()
        XCTAssertTrue(poll { !self.offer.exists })

        openPasswordProfile()
        let row = app.descendants(matching: .any).matching(identifier: "passwords.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(row.label, "localhost, alice@example.test")
    }

    func testSettingsPasswordPagesFollowSettingsHistory() {
        openSettings("passwords")
        XCTAssertTrue(app.buttons["passwords.profile.Personal"].waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(app.popUpButtons["passwords.profile"].exists)
        attachScreenshot("passwords-profiles")

        app.buttons["passwords.profile.Personal"].click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "passwords.empty").firstMatch.waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords-profile")
        app.buttons["passwords.import"].click()
        XCTAssertTrue(app.buttons["passwords.importCSV"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords-import")

        app.buttons["settings.back"].click()
        XCTAssertTrue(app.buttons["passwords.import"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["settings.back"].click()
        XCTAssertTrue(app.buttons["passwords.profile.Personal"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["settings.forward"].click()
        XCTAssertTrue(app.buttons["passwords.import"].waitForExistence(timeout: Self.renderTimeout))
    }

    func testSettingsPasswordPagesInFrenchAndRightToLeftLayout() {
        app.terminate()
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
            + ["-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"]
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))

        openSettings("passwords")
        let profile = app.buttons["passwords.profile.Personal"]
        XCTAssertTrue(profile.waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords-profiles-french-expanded-rtl")
        profile.click()
        XCTAssertTrue(app.buttons["passwords.import"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords-profile-french-expanded-rtl")
        app.buttons["passwords.import"].click()
        XCTAssertTrue(app.buttons["passwords.importCSV"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords-import-french-expanded-rtl")
    }

    // A pending username belongs to one tab and one origin, not to every password form in the browser.
    func testTwoStepUsernameDoesNotCrossTabsOrOrigins() {
        open("login-steps-username.html", expecting: "Enter your email")
        let email = app.webViews.textFields["Email address"]
        email.click()
        email.typeText("tab-owner@example.test")
        app.webViews.buttons["Next"].click()
        XCTAssertTrue(page("Enter your password").waitForExistence(timeout: Self.pageTimeout))

        open("login-steps-password.html", host: "127.0.0.1", expecting: "Enter your password")
        let secondStepPassword = app.webViews.secureTextFields["Password"]
        secondStepPassword.click()
        secondStepPassword.typeText("other-origin-secret")
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(offer.staticTexts["tab-owner@example.test"].exists, "The account cannot cross origins")
        app.buttons["passwords.notNow"].click()

        app.typeKey("t", modifierFlags: .command)
        controlBarInput.typeText(server.url("login-steps-password.html").absoluteString + "\n")
        XCTAssertTrue(page("Enter your password").waitForExistence(timeout: Self.pageTimeout))
        secondStepPassword.click()
        secondStepPassword.typeText("other-tab-secret")
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertFalse(offer.staticTexts["tab-owner@example.test"].exists, "The account cannot cross tabs")
    }

    private func signIn(as name: String, with secret: String, host: String = "localhost", reloading: Bool = false) {
        if reloading {
            app.typeKey("r", modifierFlags: .command)
            XCTAssertTrue(page("Filled nobody with 0 characters").waitForExistence(timeout: Self.pageTimeout))
        } else {
            open("login.html", host: host, expecting: "Sign in")
        }
        username.click()
        username.typeText(name)
        password.click()
        password.typeText(secret)
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(page("Signed in as \(name)").waitForExistence(timeout: Self.renderTimeout))
    }

    private func openPasswordProfile() {
        openSettings("passwords")
        let profile = app.buttons["passwords.profile.Personal"]
        XCTAssertTrue(profile.waitForExistence(timeout: Self.renderTimeout))
        profile.click()
    }
}
