import Foundation
import Testing
@testable import BrowserExtensions

// What Settings and the installation prompt say an extension cannot do. Failure modes: a feature missed because it is
// only optional or declared by a manifest key, one reported that Aero provides, and duplicates.

@Test func declaredFeaturesWithoutAnImplementationAreReportedOnce() {
    let manifest: [String: Any] = [
        "permissions": ["storage", "sidePanel", "identity", "idle", "offscreen", "notifications"],
        "optional_permissions": ["bookmarks", "downloads", "identity.email", "privacy", "contentSettings"],
        "side_panel": ["default_path": "panel.html"],
        "chrome_url_overrides": ["newtab": "tab.html"],
        "omnibox": ["keyword": "x"]
    ]
    #expect(ExtensionCapabilities.unavailableFeatures(of: manifest) == [.sidePanel, .pageOverrides, .bookmarks, .siteSettings, .addressBarKeyword])
    #expect(ExtensionCapabilities.unavailableFeatures(of: ["oauth2": ["client_id": "example"]]) == [.accountSignIn])
}

@Test func anExtensionUsingOnlyWhatAeroProvidesLosesNothing() {
    let manifest: [String: Any] = ["permissions": ["tabs", "storage", "idle", "offscreen", "downloads", "notifications", "clipboardRead", "nativeMessaging"]]
    #expect(ExtensionCapabilities.unavailableFeatures(of: manifest).isEmpty)
}

@Test func malformedDeclarationsAreIgnored() {
    #expect(ExtensionCapabilities.unavailableFeatures(of: ["permissions": "sidePanel", "optional_permissions": [1, "proxy"]]) == [.proxy])
}
