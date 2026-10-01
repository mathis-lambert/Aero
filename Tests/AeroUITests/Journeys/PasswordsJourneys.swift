import XCTest

/// Saving, filling and managing passwords, per profile. Items are created under a test creator and namespace, never
/// among real passwords. Storage, sites and CSV are covered by PasswordStoreTests and PasswordTests.
/// See docs/PASSWORDS.md › Failure modes.
@MainActor
final class PasswordsJourneys: E2ETestCase {
    private var username: XCUIElement { app.webViews.textFields["Username"] }
    private var password: XCUIElement { app.webViews.secureTextFields["Password"] }
    private var offer: XCUIElement { element("passwords.offer") }
    private var picker: XCUIElement { element("passwords.picker") }
    private var saved: XCUIElement { app.buttons["passwords.login"].firstMatch }

    /// Failure modes 4, 5, 8, 9 and 10: save, fill into the focused form, update instead of duplicating, dismiss,
    /// strong passwords, a two-step sign-in whose account stays in its tab and origin, and never for this site.
    func testSavingAndFillingFollowTheSignIn() throws {
        try launch()
        signIn(as: "alice", with: "hunter2")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout), "Submitting offers to save")
        attachScreenshot("save offer")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { !self.offer.exists })

        reload()
        username.click()
        XCTAssertTrue(saved.waitForExistence(timeout: Self.renderTimeout), "The saved login is offered under the field")
        attachScreenshot("account list")
        app.webViews.staticTexts["Sign in"].firstMatch.click()
        XCTAssertTrue(poll { !self.picker.exists }, "The list closes when the field loses focus")
        username.click()
        saved.click()
        XCTAssertTrue(page("Filled alice with 7 characters").waitForExistence(timeout: Self.renderTimeout), "Choosing it fills the form")
        XCTAssertFalse(picker.exists, "The list closes after filling")
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(page("Signed in as alice").waitForExistence(timeout: Self.renderTimeout))
        pause(1) // What must not happen: an offer appearing.
        XCTAssertFalse(offer.exists, "An unchanged password only records its use")

        signIn(as: "alice", with: "hunter3", reloading: true)
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(app.buttons["passwords.save"].label, "Update", "A known username with a new password offers Update")
        XCTAssertFalse(app.buttons["passwords.never"].exists)
        app.typeKey(.return, modifierFlags: [])
        signIn(as: "mallory", with: "secret", reloading: true)
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll { !self.offer.exists }, "Escape dismisses the offer")
        reload()
        username.click()
        XCTAssertTrue(saved.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(app.buttons.matching(identifier: "passwords.login").count, 1, "Updating kept one login and Escape saved none")
        app.typeKey(.escape, modifierFlags: [])

        open("signup.html", expecting: "Create account")
        app.webViews.secureTextFields["New password"].click()
        let suggestion = app.buttons["passwords.suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: Self.renderTimeout), "A new-password field offers a strong password")
        suggestion.click()
        XCTAssertTrue(page("Passwords match with 20 characters").waitForExistence(timeout: Self.renderTimeout), "It fills every new-password field")
        app.webViews.buttons["Create account"].click()
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout), "The new account's password is offered")
        app.buttons["passwords.notNow"].click()

        enterAccount("alice@example.test")
        secondStep("two-step-secret")
        XCTAssertTrue(offer.staticTexts["alice@example.test"].exists, "The offer names the first step's account")
        app.buttons["passwords.save"].click()
        enterAccount("tab-owner@example.test")
        open("login-steps-password.html", host: "127.0.0.1", expecting: "Enter your password")
        secondStep("other-origin-secret")
        XCTAssertFalse(offer.staticTexts["tab-owner@example.test"].exists, "The account cannot cross origins")
        app.buttons["passwords.notNow"].click()
        open("login-steps-password.html", expecting: "Enter your password")
        secondStep("other-tab-secret")
        XCTAssertFalse(offer.staticTexts["tab-owner@example.test"].exists, "The account cannot cross tabs")
        app.buttons["passwords.notNow"].click()

        signIn(as: "bob", with: "secret", host: "127.0.0.1")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.never"].click()
        XCTAssertTrue(poll { !self.offer.exists })
        quitAndRelaunch()
        signIn(as: "bob", with: "secret", host: "127.0.0.1")
        pause(1) // What must not happen: an offer appearing.
        XCTAssertFalse(offer.exists, "Never for this site survives a relaunch")
        signIn(as: "bob", with: "secret")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout), "Another site is still offered")
        app.buttons["passwords.notNow"].click()
    }

    /// Failure mode 3: a login belongs to its profile, spaces included. Settings lists, edits and deletes it with the
    /// site's icon, and its pages follow Settings' own back and forward.
    func testPasswordsStayInTheirProfileAndSettingsManagesThem() throws {
        try launch { seed in
            try seed.addSpace("Work", profile: "Work")
            try seed.addSpace("Reading", profile: "Work")
        }
        signIn(as: "carol", with: "before-edit")
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
        app.buttons["passwords.save"].click()
        for name in ["Work", "Reading"] {
            space(name).click()
            open("login.html", expecting: "Sign in")
            username.click()
            pause(1) // What must not happen: an offer appearing.
            XCTAssertFalse(saved.exists, "\(name), in another profile, is not offered the login")
        }
        space("Main").click()
        open("login.html", expecting: "Sign in")
        username.click()
        XCTAssertTrue(saved.waitForExistence(timeout: Self.renderTimeout), "The profile's own space is")
        app.typeKey(.escape, modifierFlags: [])

        openSettings("passwords")
        XCTAssertTrue(app.buttons["passwords.profile.Personal"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("passwords profiles", of: app)
        app.buttons["passwords.profile.Personal"].click()
        let row = element("passwords.row")
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(row.label, "localhost, carol")
        let orange = ScreenshotColor(red: 255, green: 90, blue: 0)
        XCTAssertTrue(poll { orange.isShown(in: row, at: CGPoint(x: 26, y: row.frame.height / 2)) }, "The login shows the site's icon")
        app.buttons["passwords.import"].click()
        XCTAssertTrue(app.buttons["passwords.importCSV"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["settings.back"].click()
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout), "Back returns to the profile")
        app.buttons["settings.back"].click()
        XCTAssertTrue(app.buttons["passwords.profile.Personal"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["settings.forward"].click()
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout), "Forward goes back in")

        row.click()
        XCTAssertTrue(app.buttons["passwords.reveal"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("login", of: app)
        app.buttons["passwords.reveal"].click()
        let editor = app.textFields["passwords.edit.password"]
        replaceText(of: editor, with: "after-edit")
        app.buttons["passwords.edit.save"].click()
        XCTAssertTrue(app.buttons["passwords.reveal"].waitForExistence(timeout: Self.renderTimeout), "Saving closes the editor safely")
        app.buttons["passwords.reveal"].click()
        XCTAssertTrue(editor.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(editor.value as? String, "after-edit", "The edit reached the test keychain")
        app.typeKey(.escape, modifierFlags: [])
        app.buttons["passwords.delete"].click()
        let confirm = app.buttons["passwords.confirmDelete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.renderTimeout), "Deleting asks first")
        confirm.click()
        XCTAssertTrue(element("passwords.empty").waitForExistence(timeout: Self.renderTimeout))
        closeSettings()

        reload(expecting: "Sign in")
        username.click()
        pause(1) // What must not happen: an offer appearing.
        XCTAssertFalse(saved.exists, "A deleted login is not offered")
    }

    // MARK: - Helpers

    private func signIn(as name: String, with secret: String, host: String = "localhost", reloading: Bool = false) {
        if reloading { reload() } else { open("login.html", host: host, expecting: "Sign in") }
        username.click()
        // A saved login opens the account list, which briefly re-attaches the page for accessibility.
        XCTAssertTrue(username.waitForExistence(timeout: Self.renderTimeout))
        username.typeText(name)
        password.click()
        password.typeText(secret)
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(page("Signed in as \(name)").waitForExistence(timeout: Self.renderTimeout))
    }

    private func reload(expecting text: String = "Filled nobody with 0 characters") {
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(page(text).waitForExistence(timeout: Self.pageTimeout))
    }

    private func secondStep(_ secret: String) {
        let field = app.webViews.secureTextFields["Password"]
        field.click()
        field.typeText(secret)
        app.webViews.buttons["Sign in"].click()
        XCTAssertTrue(offer.waitForExistence(timeout: Self.renderTimeout))
    }

    /// The first page of a two-step sign-in, which asks only for the account.
    private func enterAccount(_ account: String) {
        open("login-steps-username.html", expecting: "Enter your email")
        let email = app.webViews.textFields["Email address"]
        email.click()
        email.typeText(account)
        app.webViews.buttons["Next"].click()
        XCTAssertTrue(page("Enter your password").waitForExistence(timeout: Self.pageTimeout))
    }
}
