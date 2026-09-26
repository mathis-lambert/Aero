import XCTest

/// Launch configuration shared by UI tests: isolated data and a fixed language.
@MainActor
enum TestApplication {
    static let testDataKey = "AERO_TEST_DATA"
    /// Points every search engine at the fixture server; honored only with `AERO_TEST_DATA`.
    static let searchEndpointKey = "AERO_TEST_SEARCH"
    /// The only filter list ad blocking downloads; honored only with `AERO_TEST_DATA`.
    static let filterListKey = "AERO_TEST_FILTERS"
    /// The only folder native messaging hosts are read from; honored only with `AERO_TEST_DATA`.
    static let nativeHostsKey = "AERO_TEST_NATIVE_HOSTS"
    static let launchTimeout: TimeInterval = 10

    static func make() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[testDataKey] = NSTemporaryDirectory() + "AeroUITests-" + UUID().uuidString
        app.launchArguments = launchArguments(language: "en", locale: "en_US")
        return app
    }

    /// Scroll bars always show, so a test can scroll by clicking their track: scroll events from the test
    /// runner never reach the app.
    static func launchArguments(language: String, locale: String) -> [String] {
        ["-AppleLanguages", "(\(language))", "-AppleLocale", locale, "-AppleShowScrollBars", "Always"]
    }
}
