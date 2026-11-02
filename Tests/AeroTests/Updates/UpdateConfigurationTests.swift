import Foundation
import Testing
@testable import Aero

// docs/UPDATES.md. Failure modes: tests or source builds contact production; a distribution of another identity, or
// with an invalid key, starts an updater that cannot verify updates; the chosen channel is lost, or an unreadable one
// leaves no channel.
@MainActor
struct UpdateConfigurationTests {
    private func info() -> [String: Any] {
        ["AeroUpdatesEnabled": "YES", "CFBundleIdentifier": "app.getaero.browser",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()]
    }

    @Test func isolation() {
        #expect(UpdateConfiguration(info: info(), isTestRun: true) == .disabled)
        var source = info(); source["AeroUpdatesEnabled"] = "NO"
        #expect(UpdateConfiguration(info: source, isTestRun: false) == .disabled)
        #expect(UpdateConfiguration(info: info(), isTestRun: false) == .enabled)
    }

    @Test func rejectsInvalidDistribution() {
        for (key, value) in [("CFBundleIdentifier", "app.getaero.browser.debug"), ("SUPublicEDKey", "missing")] {
            var broken = info(); broken[key] = value
            #expect(UpdateConfiguration(info: broken, isTestRun: false) == .invalid)
        }
    }

    @Test func theChosenChannelIsKept() throws {
        let namespace = "updates-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: "app.getaero.browser.tests." + namespace) }
        let preferences = BrowserPreferences(testNamespace: namespace)
        #expect(preferences.updateChannel == .stable, "Stable until chosen otherwise")
        preferences.updateChannel = .nightly
        #expect(BrowserPreferences(testNamespace: namespace).updateChannel == .nightly)
        let suite = try #require(UserDefaults(suiteName: "app.getaero.browser.tests." + namespace))
        suite.set("canary", forKey: "browser.updates.channel")
        #expect(BrowserPreferences(testNamespace: namespace).updateChannel == .stable, "An unreadable channel is the stable one")
    }
}
