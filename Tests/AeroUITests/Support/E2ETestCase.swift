import AppKit
import os
import XCTest

/// The base of every journey: a fixture server and an app whose data lives in a folder of its own.
/// Nothing launches until the journey calls `launch`, so it can first seed records or choose a language.
/// Journeys are synchronous, so their first failed assertion ends them. See docs/TESTING.md.
@MainActor
class E2ETestCase: XCTestCase {
    static let launchTimeout: TimeInterval = 10
    static let pageTimeout: TimeInterval = 10
    static let renderTimeout: TimeInterval = 5
    private static let pollInterval: TimeInterval = 0.2

    /// Travels with the test products; Cloud runs tests separately from the source checkout.
    static let fixtures = Bundle(for: E2ETestCase.self).bundleURL.appendingPathComponent("Contents/Resources/Fixtures", isDirectory: true)

    private(set) var app: XCUIApplication!
    private(set) var server: FixtureServer!
    /// `AERO_TEST_DATA`: the run's records, caches, downloads and preferences namespace.
    private(set) var dataRoot: URL!
    private var options = Launch()

    override func setUp() async throws {
        continueAfterFailure = false
        guard FileManager.default.fileExists(atPath: Self.fixtures.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: Self.fixtures.path])
        }
        server = try FixtureServer()
        dataRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AeroUITests-\(UUID().uuidString)", isDirectory: true)
        app = XCUIApplication()
        app.launchEnvironment = [
            "AERO_TEST_DATA": dataRoot.path,
            "AERO_TEST_SEARCH": server.searchEndpoint.absoluteString,
            "AERO_TEST_FILTERS": server.url("filters.txt").absoluteString,
            "AERO_TEST_NATIVE_HOSTS": Self.fixtures.appendingPathComponent("native-hosts").path,
            "AERO_TEST_IMPORT_SOURCES": Self.fixtures.appendingPathComponent("import-sources").path
        ]
    }

    override func tearDown() async throws {
        app?.terminate()
        server?.stop()
    }

    // MARK: - Launching

    /// How the app starts: its language and layout, its appearance, and the screen it must reach.
    struct Launch {
        enum Screen { case browser, onboarding, recovery }

        var french = false
        /// `-NSDoubleLocalizedStrings`: every string twice as long, to show what does not fit.
        var expandedStrings = false
        var rightToLeft = false
        var dark = false
        var screen = Screen.browser

        var arguments: [String] {
            var arguments = french ? ["-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR"] : ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            // Scroll bars always show, so a journey can scroll by clicking their track: the runner's scroll events never reach the app.
            arguments += ["-AppleShowScrollBars", "Always"]
            if expandedStrings { arguments += ["-NSDoubleLocalizedStrings", "YES"] }
            if rightToLeft { arguments += ["-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"] }
            if dark { arguments += ["-browser.appearance", "dark"] }
            return arguments
        }
    }

    /// Launches with `options`, after `seed` writes its records through Aero's own store.
    func launch(_ options: Launch = Launch(), seed: ((inout Seed) throws -> Void)? = nil) throws {
        if let seed {
            var records = Seed(server: server)
            try seed(&records)
            try write(records)
        }
        self.options = options
        app.launchEnvironment["AERO_TEST_ONBOARDING"] = options.screen == .onboarding ? "1" : nil
        app.launchArguments = options.arguments
        app.launch()
        waitForScreen()
    }

    /// Launches again with the same options, after a crash-like exit that skips the quit prompt.
    func relaunch(_ change: (inout Launch) -> Void = { _ in }) {
        app.terminate()
        change(&options)
        app.launchArguments = options.arguments
        app.launch()
        waitForScreen()
    }

    /// Quits from the prompt, so the session is saved, then launches again.
    func quitAndRelaunch(_ change: (inout Launch) -> Void = { _ in }) {
        quit()
        change(&options)
        app.launchArguments = options.arguments
        app.launch()
        waitForScreen()
    }

    func quit() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.groups["quit.prompt"].waitForExistence(timeout: Self.renderTimeout), "⌘Q asks first")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout), "Return quits")
    }

    /// The store is an actor: its write runs apart while the test waits for it, with a deadline.
    private func write(_ records: Seed) throws {
        let root = try XCTUnwrap(dataRoot)
        let outcome = OSAllocatedUnfairLock<Result<Void, any Error>?>(initialState: nil)
        let written = expectation(description: "The seed is written")
        Task.detached {
            do { try await records.write(to: root); outcome.withLock { $0 = .success(()) } }
            catch { outcome.withLock { $0 = .failure(error) } }
            written.fulfill()
        }
        wait(for: [written], timeout: Self.launchTimeout)
        try XCTUnwrap(outcome.withLock { $0 }, "The seed was not written in time").get()
    }

    private func waitForScreen() {
        let element = switch options.screen {
        case .browser: controlBarInput
        case .onboarding: app.groups["onboarding"]
        case .recovery: app.buttons["storage.retry"]
        }
        XCTAssertTrue(element.waitForExistence(timeout: Self.launchTimeout), "Aero reaches its \(options.screen) screen")
    }

    // MARK: - Reading the app

    var controlBarInput: XCUIElement { app.textFields["controlBar.input"] }
    var tabRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.tab") }
    var favoriteRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.favorite") }
    var tiles: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.tile") }
    var groupHeaders: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.group") }

    /// Text shown by the selected tab's page.
    func page(_ text: String) -> XCUIElement { app.webViews.staticTexts[text] }

    func space(_ name: String) -> XCUIElement { app.buttons.matching(identifier: "sidebar.space")[name] }

    func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

    /// A native toggle's state, which accessibility reports as 1 or 0.
    func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? NSNumber)?.boolValue ?? (toggle.value as? String == "1")
    }

    /// Labels of the elements with `identifier`, in reading order, from one snapshot of the app, so a
    /// list that reloads during the query cannot fail it halfway.
    func labels(of identifier: String) -> [String] {
        guard let snapshot = try? app.snapshot() else { return [] }
        var matches: [any XCUIElementSnapshot] = []
        func collect(_ element: any XCUIElementSnapshot) {
            if element.identifier == identifier { matches.append(element) }
            element.children.forEach(collect)
        }
        collect(snapshot)
        return matches.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map(\.label)
    }

    func poll(timeout: TimeInterval = renderTimeout, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(Self.pollInterval))
        }
        return condition()
    }

    /// Lets time pass where nothing observable can be waited for, such as a request that must not happen.
    func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: .now.addingTimeInterval(seconds)) }

    // MARK: - Acting

    /// Opens `fixture` in a new tab from the control bar.
    func open(_ fixture: String, host: String = "localhost", expecting text: String) {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        controlBarInput.typeText(server.url(fixture, host: host).absoluteString + "\n")
        XCTAssertTrue(page(text).waitForExistence(timeout: Self.pageTimeout), "\(fixture) loaded")
    }

    /// Hands `url` to the running Aero as another app would. `XCUIApplication.open` would launch a second instance.
    func openFromAnotherApp(_ url: URL) {
        // Journeys run the Aero Dev scheme (docs/TESTING.md).
        guard let bundle = NSRunningApplication.runningApplications(withBundleIdentifier: "app.getaero.browser.debug").first?.bundleURL else {
            return XCTFail("Aero is running")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: bundle, configuration: configuration)
    }

    /// Runs a command from the command bar, as someone who does not know its shortcut would.
    func runCommand(_ title: String) {
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        // Short of the whole title, which would also be a search row with the same label.
        controlBarInput.typeText(String(title.trimmingCharacters(in: CharacterSet(charactersIn: "…")).dropLast()))
        let item = app.descendants(matching: .any).matching(identifier: "controlBar.item")[title]
        XCTAssertTrue(item.waitForExistence(timeout: Self.renderTimeout), "The command bar offers \(title)")
        item.click()
    }

    /// Chooses `item` in the menu bar's `menu`.
    func chooseInMenuBar(_ menu: String, _ item: String) {
        let bar = app.menuBars.menuBarItems[menu]
        bar.click()
        bar.menus.menuItems[item].click()
    }

    /// Chooses `item` in `element`'s context menu, whose titles the menu bar may share.
    func chooseInContextMenu(of element: XCUIElement, _ item: String) {
        element.rightClick()
        let choice = app.windows.menuItems[item]
        XCTAssertTrue(choice.waitForExistence(timeout: Self.renderTimeout), "The context menu shows \(item)")
        choice.click()
    }

    /// Chooses `item` in the submenu `submenu` of the open menu: a context menu's by default, or the menu bar's.
    func chooseInSubmenu(_ submenu: String, _ item: String, in menus: XCUIElementQuery? = nil) {
        let menus = menus ?? app.windows
        menus.menuItems[submenu].click()
        let choice = menus.menuItems[submenu].menuItems[item]
        XCTAssertTrue(choice.waitForExistence(timeout: Self.renderTimeout), "\(submenu) shows \(item)")
        choice.click()
    }

    /// Replaces the text of `field`, such as a name being edited.
    func replaceText(of field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: Self.renderTimeout))
        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText(text)
    }

    /// Creates a space from the sidebar, in a new profile when `newProfile` names one.
    func createSpace(_ name: String, newProfile: String? = nil) {
        app.buttons["sidebar.addSpace"].click()
        let field = app.textFields["spaces.name"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.renderTimeout))
        field.click()
        field.typeText(name)
        if let newProfile {
            app.buttons["spaces.newProfile"].click()
            app.textFields["spaces.profileName"].click()
            app.typeText(newProfile)
        }
        app.buttons["spaces.save"].click()
        XCTAssertTrue(poll { self.space(name).isSelected && !self.app.buttons["spaces.save"].exists })
    }

    // MARK: - Settings

    /// Opens the Settings window on a language-independent section identifier, from the application menu: a page
    /// may claim Command-comma.
    func openSettings(_ section: String? = nil) {
        let applicationMenu = app.menuBars.menuBarItems.element(boundBy: 1)
        applicationMenu.click()
        applicationMenu.menus.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@ OR title BEGINSWITH %@", "Settings", "Réglages")).firstMatch.click()
        if let section { selectSettingsSection(section) }
    }

    func selectSettingsSection(_ section: String) {
        let row = element("settings.section.\(section.lowercased())")
        XCTAssertTrue(row.waitForExistence(timeout: Self.renderTimeout), "Settings shows its \(section) section")
        row.click()
    }

    func closeSettings() { app.typeKey("w", modifierFlags: .command) }

    /// Settings pages scroll: clicking below the scroll bar's knob pages down until `element` is on screen.
    @discardableResult
    func reveal(_ element: XCUIElement) -> XCUIElement {
        let track = app.windows.firstMatch.scrollBars.firstMatch
        for _ in 0..<5 where !element.isHittable {
            track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)).click()
        }
        return element
    }

    // MARK: - Evidence

    func attachScreenshot(_ name: String, of element: XCUIElement? = nil) {
        keep(XCTAttachment(screenshot: (element ?? app.windows.firstMatch).screenshot()), named: name)
    }

    /// Menus and popovers outside the window: the whole screen.
    func attachScreen(_ name: String) { keep(XCTAttachment(screenshot: XCUIScreen.main.screenshot()), named: name) }

    func attachText(_ text: String, named name: String) { keep(XCTAttachment(string: text), named: name) }

    private func keep(_ attachment: XCTAttachment, named name: String) {
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
