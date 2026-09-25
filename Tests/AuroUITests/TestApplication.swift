import XCTest

/// Launch configuration shared by UI tests: isolated data and a fixed language.
@MainActor
enum TestApplication {
    static let testDataKey = "AURO_TEST_DATA"
    static let launchTimeout: TimeInterval = 10

    static func make(language: String = "en", locale: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment[testDataKey] = NSTemporaryDirectory() + "AuroUITests-" + UUID().uuidString
        app.launchArguments = languageArguments(language: language, locale: locale)
        return app
    }

    static func languageArguments(language: String, locale: String) -> [String] {
        ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
    }
}
