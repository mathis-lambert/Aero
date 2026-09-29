import Foundation
import Testing
@testable import Aero

// Failure modes: tests or source builds contact production; an unknown channel or mismatched
// identity switches applications; an invalid key/feed starts an updater that cannot verify updates.
struct UpdateConfigurationTests {
    private func info(channel: String = "stable") -> [String: Any] {
        ["AeroUpdatesEnabled": "YES", "AeroChannel": channel,
         "CFBundleIdentifier": "app.getaero.browser" + (channel == "stable" ? "" : "." + channel),
         "SUFeedURL": "https://getaero.app/updates/\(channel).xml",
         "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString()]
    }

    @Test func isolation() {
        #expect(UpdateConfiguration(info: info(), isTestRun: true) == .disabled)
        var source = info(); source["AeroUpdatesEnabled"] = "NO"
        #expect(UpdateConfiguration(info: source, isTestRun: false) == .disabled)
    }

    @Test(arguments: ["stable", "beta", "nightly"])
    func validChannels(channel: String) {
        #expect(UpdateConfiguration(info: info(channel: channel), isTestRun: false) == .enabled)
    }

    @Test func rejectsInvalidDistribution() {
        for (key, value) in [("AeroChannel", "dev"), ("CFBundleIdentifier", "app.getaero.browser.beta"),
                             ("SUFeedURL", "http://getaero.app/updates/stable.xml"),
                             ("SUFeedURL", "https://getaero.app/updates/beta.xml"), ("SUPublicEDKey", "missing")] {
            var broken = info(); broken[key] = value
            #expect(UpdateConfiguration(info: broken, isTestRun: false) == .invalid)
        }
    }
}
