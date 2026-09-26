import XCTest

/// Shared setup for end-to-end tests: a fixture server, an isolated app launch and helpers.
@MainActor
class BrowserE2ETestCase: XCTestCase {
    static let pageTimeout: TimeInterval = 10
    static let renderTimeout: TimeInterval = 5
    private static let pollInterval: TimeInterval = 0.2

    var app: XCUIApplication!
    var server: FixtureServer!

    override func setUp() async throws {
        continueAfterFailure = false
        server = try FixtureServer()
        app = TestApplication.make()
        app.launchEnvironment[TestApplication.searchEndpointKey] = server.searchEndpoint.absoluteString
        app.launchEnvironment[TestApplication.filterListKey] = server.url("filters.txt").absoluteString
        app.launchEnvironment[TestApplication.nativeHostsKey] = Self.fixtures.appendingPathComponent("native-hosts").path
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    override func tearDown() async throws {
        app.terminate()
        server.stop()
    }

    /// Fixtures read by the app itself, from the repository: the sandboxed runner has no folder the app may read.
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures", isDirectory: true)

    var controlBarInput: XCUIElement { app.textFields["controlBar.input"] }

    /// Text shown by the selected tab's page.
    func page(_ text: String) -> XCUIElement { app.webViews.staticTexts[text] }

    /// Lets time pass where nothing observable can be waited for, such as a request that must not happen.
    func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: .now.addingTimeInterval(seconds)) }
    var tabRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.tab") }

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

    func open(_ fixture: String, host: String = "localhost", expecting text: String) {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        controlBarInput.typeText(server.url(fixture, host: host).absoluteString + "\n")
        XCTAssertTrue(app.webViews.staticTexts[text].waitForExistence(timeout: Self.pageTimeout), "\(fixture) loaded")
    }

    func relaunch() {
        app.terminate()
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    /// Opens the native Settings window, on the tab titled `section` when given.
    func openSettings(_ section: String? = nil) {
        app.typeKey(",", modifierFlags: .command)
        guard let section else { return }
        let tab = app.toolbars.buttons[section]
        XCTAssertTrue(tab.waitForExistence(timeout: Self.renderTimeout), "Settings shows its \(section) tab")
        tab.click()
    }

    func closeSettings() {
        app.typeKey("w", modifierFlags: .command)
    }

    /// Quits from the prompt, so the session is saved, then launches again.
    func quitAndRelaunch() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.groups["quit.prompt"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout))
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    func poll(timeout: TimeInterval = renderTimeout, _ condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if condition() { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(Self.pollInterval))
        }
        return condition()
    }

    func attachScreenshot(_ name: String, of element: XCUIElement? = nil) {
        let attachment = XCTAttachment(screenshot: (element ?? app.windows.firstMatch).screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
