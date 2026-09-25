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
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    override func tearDown() async throws {
        app.terminate()
        server.stop()
    }

    var controlBarInput: XCUIElement { app.textFields["controlBar.input"] }
    var tabRows: XCUIElementQuery { app.buttons.matching(identifier: "sidebar.tab") }

    /// Labels of the elements with `identifier`, in reading order, from one snapshot of `root`, so a
    /// list that reloads during the query cannot fail it halfway.
    func labels(of identifier: String, in root: XCUIElement? = nil) -> [String] {
        guard let snapshot = try? (root ?? app).snapshot() else { return [] }
        var matches: [any XCUIElementSnapshot] = []
        func collect(_ element: any XCUIElementSnapshot) {
            if element.identifier == identifier { matches.append(element) }
            element.children.forEach(collect)
        }
        collect(snapshot)
        return matches.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }.map(\.label)
    }

    func open(_ fixture: String, expecting text: String) {
        app.typeKey("t", modifierFlags: .command)
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.renderTimeout))
        controlBarInput.typeText(server.url(fixture).absoluteString + "\n")
        XCTAssertTrue(app.webViews.staticTexts[text].waitForExistence(timeout: Self.pageTimeout), "\(fixture) loaded")
    }

    func relaunch() {
        app.terminate()
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
